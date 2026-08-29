local Banking = {}
local playerControllers = setmetatable({}, { __mode = "k" })

local function ProviderName()
	local configured = Config and Config.Use and Config.Use.Bank or Config and Config.Banking and Config.Banking.Provider or "qb"
	configured = tostring(configured):lower()
	if configured == "m" or configured == "m-bank" or configured == "m-banking" then return "mbank" end
	if configured == "qb-core" or configured == "qbcore" then return "qb" end
	return configured
end

local function Failure(errorCode) return { ok = false, error = tostring(errorCode or "banking_unavailable") } end

local function AddLegacyKeys(account)
	if type(account) ~= "table" then return account end
	local fields = { playerId = "PlayerID", accountId = "AccountId", planId = "PlanId", balance = "Balance", cardNumber = "CardNumber", holderName = "HolderName", cardStatus = "CardStatus" }
	for modern, legacy in pairs(fields) do account[legacy] = account[modern] end
	return account
end

local function MCall(methodName, ...)
	if ProviderName() ~= "mbank" then return nil, "unsupported_bank_provider:" .. ProviderName() end
	if not exports then return nil, "banking_unavailable" end
	local resource = tostring(Config and Config.Banking and Config.Banking.Resource or "m-banking")
	local okProvider, provider = pcall(function() return exports[resource] end)
	if not okProvider or not provider then return nil, "banking_unavailable" end
	local okMethod, method = pcall(function() return provider[methodName] end)
	if not okMethod or method == nil then return nil, "banking_export_missing:" .. tostring(methodName) end
	local ok, first, second, third = pcall(method, provider, ...)
	if not ok then return nil, tostring(first) end
	return first, second, third
end

local function QBExport()
	if not exports then return nil end
	local ok, provider = pcall(function() return exports["qb-core"] end)
	return ok and provider or nil
end

local function QBCall(methodName, ...)
	local provider = QBExport()
	if not provider then return nil end
	local okMethod, method = pcall(function() return provider[methodName] end)
	if not okMethod or method == nil then return nil end
	local ok, result = pcall(method, provider, ...)
	return ok and result or nil
end

local function QBInvokePlayer(controller, methodName, ...)
	local provider = QBExport()
	if not provider or not controller then return false end
	local args = { n = select("#", ...), ... }
	local ok, result = pcall(function()
		return provider:Player(controller, methodName, table.unpack(args, 1, args.n))
	end)
	return ok and result ~= false
end

local function PlayerData(player) return type(player) == "table" and type(player.PlayerData) == "table" and player.PlayerData or nil end

local function TrackPlayer(player, controller)
	local data = PlayerData(player)
	if not data then return nil end
	local resolvedController = controller or data.source
	if resolvedController ~= nil then playerControllers[player] = resolvedController end
	return player
end

local function QBPlayer(controller)
	local player = QBCall("GetPlayer", controller)
	return TrackPlayer(player, controller)
end

local function PlayerMatchesId(player, playerId)
	local data = PlayerData(player)
	if not data then return false end
	local wanted = tostring(playerId or "")
	local raw = wanted:gsub("^helix:", "")
	if tostring(data.citizenid or "") == wanted or tostring(data.citizenid or "") == raw
		or tostring(data.license or "") == wanted or tostring(data.license or "") == raw
	then
		return true
	end
	local source = data.source
	if source == nil then return false end
	local okState, playerState = pcall(function() return source:GetLyraPlayerState() end)
	if not okState or not playerState then return false end
	local okId, helixId = pcall(function() return playerState:GetHelixUserId() end)
	if not okId then return false end
	return tostring(helixId or "") == wanted or tostring(helixId or "") == raw
end

local function QBPlayerById(playerId)
	local direct = QBCall("GetPlayerByCitizenId", tostring(playerId or ""))
	if PlayerData(direct) then return TrackPlayer(direct) end
	local players = QBCall("GetQBPlayers")
	if type(players) == "table" then
		for controller, player in pairs(players) do
			if PlayerMatchesId(player, playerId) then return TrackPlayer(player, controller) end
		end
	end
	return nil
end

local function QBPlayerByAccount(accountId)
	local direct = QBCall("GetPlayerByAccount", tostring(accountId or ""))
	if PlayerData(direct) then return TrackPlayer(direct) end
	local players = QBCall("GetQBPlayers")
	if type(players) ~= "table" then return nil end
	for controller, player in pairs(players) do
		local data = PlayerData(player)
		local charinfo = data and type(data.charinfo) == "table" and data.charinfo or {}
		local citizenId = tostring(data and data.citizenid or "")
		local candidate = tostring(charinfo.account or "")
		if candidate == "" and citizenId ~= "" then candidate = "QB-" .. citizenId end
		if candidate == tostring(accountId or "") then return TrackPlayer(player, controller) end
	end
	return nil
end

local function PlayerId(player)
	local data = PlayerData(player) or {}
	return tostring(data.citizenid or data.license or "")
end

local function AccountId(player)
	local data = PlayerData(player) or {}
	local charinfo = type(data.charinfo) == "table" and data.charinfo or {}
	local account = tostring(charinfo.account or "")
	return account ~= "" and account or ("QB-" .. PlayerId(player))
end

local function HolderName(player)
	local data = PlayerData(player) or {}
	local charinfo = type(data.charinfo) == "table" and data.charinfo or {}
	local name = (tostring(charinfo.firstname or "") .. " " .. tostring(charinfo.lastname or "")):match("^%s*(.-)%s*$")
	return name ~= "" and name or tostring(data.name or "Unknown")
end

local function MoneyDollars(player, moneyType)
	local data = PlayerData(player) or {}
	local money = type(data.money) == "table" and data.money or {}
	return math.max(0, tonumber(money[moneyType]) or 0)
end

local function InvokePlayer(player, methodName, ...)
	local functions = type(player) == "table" and player.Functions or nil
	if functions ~= nil then
		local okMethod, method = pcall(function() return functions[methodName] end)
		if okMethod and method ~= nil then
			local ok, result = pcall(method, ...)
			if ok and result ~= false then return true end
		end
	end
	local data = PlayerData(player)
	local controller = playerControllers[player] or data and data.source
	if not controller then return false end
	return QBInvokePlayer(controller, methodName, ...)
end

local function SetMoney(player, moneyType, dollars)
	local data = PlayerData(player)
	if not data then return false end
	local money = {}
	for key, value in pairs(type(data.money) == "table" and data.money or {}) do money[key] = value end
	money[moneyType] = math.max(0, tonumber(dollars) or 0)
	if not InvokePlayer(player, "SetPlayerData", "money", money) then return false end
	InvokePlayer(player, "Save")
	return true
end

local function QBAccount(player)
	if not PlayerData(player) then return nil end
	return AddLegacyKeys({ playerId = PlayerId(player), accountId = AccountId(player), planId = "bronze", balance = math.floor(MoneyDollars(player, "bank") * 100), holderName = HolderName(player), cardNumber = AccountId(player), cardStatus = "active" })
end

local function QBProfile(player)
	local account = QBAccount(player)
	if not account then return Failure("player_not_found") end
	return { ok = true, profile = { hasAccount = true, accountId = account.accountId, planId = "bronze", balance = account.balance, holderName = account.holderName, transactions = {}, card = { cardNumber = account.accountId, masked = account.accountId, last4 = account.accountId:sub(-4), holderName = account.holderName, startsWith4 = account.accountId:sub(1, 4), expires = "--/--" } } }
end

local function QBMoneyResult(player, amountPence, credit, reference)
	if not PlayerData(player) then return Failure("player_not_found") end
	local amount = math.max(0, math.floor(tonumber(amountPence) or 0))
	if amount <= 0 then return Failure("invalid_amount") end
	local before = math.floor(MoneyDollars(player, "bank") * 100)
	if not credit and before < amount then return { ok = false, error = "not_enough_money", balance = before } end
	local after = credit and before + amount or before - amount
	if not SetMoney(player, "bank", after / 100) then return Failure("money_api_unavailable") end
	return { ok = true, balanceBefore = before, balanceAfter = after, balancePence = after, txId = "qb-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999)), reference = tostring(reference or "Bank transaction") }
end

local function Result(methodName, ...)
	local result, errorCode = MCall(methodName, ...)
	return result or Failure(errorCode)
end

function Banking.Provider() return ProviderName() end
function Banking.IsReady()
	if ProviderName() == "qb" then return QBExport() ~= nil end
	return MCall("IsReady") == true
end
function Banking.GetAccountByPlayerId(playerId)
	if ProviderName() == "qb" then return QBAccount(QBPlayerById(playerId)) end
	return AddLegacyKeys(MCall("GetAccountByPlayerId", playerId))
end
function Banking.GetAccountByAccountId(accountId)
	if ProviderName() == "qb" then return QBAccount(QBPlayerByAccount(accountId)) end
	return AddLegacyKeys(MCall("GetAccountByAccountId", accountId))
end
function Banking.GetProfile(controller, historyLimit) return ProviderName() == "qb" and QBProfile(QBPlayer(controller)) or Result("GetProfile", controller, historyLimit) end
function Banking.GetProfileByPlayerId(playerId, historyLimit) return ProviderName() == "qb" and QBProfile(QBPlayerById(playerId)) or Result("GetProfileByPlayerId", playerId, historyLimit) end
function Banking.CreateAccount(controller, data)
	if ProviderName() ~= "qb" then return Result("CreateAccount", controller, data) end
	local result = QBProfile(QBPlayer(controller))
	return result.ok and { ok = true, reused = true, account = result.profile } or result
end
function Banking.ValidateRecipient(accountId)
	if ProviderName() ~= "qb" then return Result("ValidateRecipient", accountId) end
	local account = QBAccount(QBPlayerByAccount(accountId))
	return account and { ok = true, exists = true, accountId = account.accountId, holderName = account.holderName, playerId = account.playerId } or { ok = true, exists = false }
end
function Banking.GetHistory(controller, limit) return ProviderName() == "qb" and { ok = true, data = {} } or Result("GetHistory", controller, limit) end
function Banking.GetHistoryByPlayerId(playerId, limit) return ProviderName() == "qb" and { ok = true, data = {} } or Result("GetHistoryByPlayerId", playerId, limit) end
function Banking.GetRecentRecipients(controller, limit) return ProviderName() == "qb" and { ok = true, data = {} } or Result("GetRecentRecipients", controller, limit) end
function Banking.GetRecentRecipientsByPlayerId(playerId, limit) return ProviderName() == "qb" and { ok = true, data = {} } or Result("GetRecentRecipientsByPlayerId", playerId, limit) end
function Banking.GetBalance(controller)
	if ProviderName() ~= "qb" then return Result("GetBalance", controller) end
	local player = QBPlayer(controller)
	return player and { ok = true, balancePence = math.floor(MoneyDollars(player, "bank") * 100) } or Failure("player_not_found")
end
function Banking.GetBalanceByPlayerId(playerId)
	if ProviderName() ~= "qb" then return Result("GetBalanceByPlayerId", playerId) end
	local player = QBPlayerById(playerId)
	return player and { ok = true, balancePence = math.floor(MoneyDollars(player, "bank") * 100) } or Failure("player_not_found")
end
function Banking.Credit(controller, amountPence, reference, extra) return ProviderName() == "qb" and QBMoneyResult(QBPlayer(controller), amountPence, true, reference) or Result("Credit", controller, amountPence, reference, extra) end
function Banking.CreditByPlayerId(playerId, amountPence, reference, extra) return ProviderName() == "qb" and QBMoneyResult(QBPlayerById(playerId), amountPence, true, reference) or Result("CreditByPlayerId", playerId, amountPence, reference, extra) end
function Banking.Debit(controller, amountPence, reference, extra) return ProviderName() == "qb" and QBMoneyResult(QBPlayer(controller), amountPence, false, reference) or Result("Debit", controller, amountPence, reference, extra) end
function Banking.DebitByPlayerId(playerId, amountPence, reference, extra) return ProviderName() == "qb" and QBMoneyResult(QBPlayerById(playerId), amountPence, false, reference) or Result("DebitByPlayerId", playerId, amountPence, reference, extra) end
function Banking.Clear(controller, reference, extra)
	if ProviderName() ~= "qb" then return Result("Clear", controller, reference, extra) end
	local player = QBPlayer(controller)
	local before = player and math.floor(MoneyDollars(player, "bank") * 100) or 0
	return player and SetMoney(player, "bank", 0) and { ok = true, balanceBefore = before, balanceAfter = 0, balancePence = 0 } or Failure("money_api_unavailable")
end
function Banking.ClearByPlayerId(playerId, reference, extra)
	if ProviderName() ~= "qb" then return Result("ClearByPlayerId", playerId, reference, extra) end
	local player = QBPlayerById(playerId)
	local before = player and math.floor(MoneyDollars(player, "bank") * 100) or 0
	return player and SetMoney(player, "bank", 0) and { ok = true, balanceBefore = before, balanceAfter = 0, balancePence = 0 } or Failure("money_api_unavailable")
end

local function QBTransfer(player, data)
	data = type(data) == "table" and data or {}
	local recipient = QBPlayerByAccount(data.recipientAccount)
	if not recipient then return Failure("recipient_not_found") end
	if recipient == player then return Failure("same_account") end
	local amount = math.max(0, math.floor(tonumber(data.amount) or 0))
	local debit = QBMoneyResult(player, amount, false, data.reference)
	if not debit.ok then return debit end
	local credit = QBMoneyResult(recipient, amount, true, data.reference)
	if not credit.ok then QBMoneyResult(player, amount, true, "Transfer reversal") return Failure("recipient_credit_failed") end
	debit.groupId = debit.txId
	return debit
end
function Banking.Transfer(controller, data) return ProviderName() == "qb" and QBTransfer(QBPlayer(controller), data) or Result("Transfer", controller, data) end
function Banking.TransferByPlayerId(playerId, data) return ProviderName() == "qb" and QBTransfer(QBPlayerById(playerId), data) or Result("TransferByPlayerId", playerId, data) end

function Banking.GetAtmProfile(controller, definition)
	if ProviderName() ~= "qb" then return Result("GetAtmProfile", controller, definition) end
	local player = QBPlayer(controller)
	return player and { ok = true, profile = { balancePence = math.floor(MoneyDollars(player, "bank") * 100), cashPence = math.floor(MoneyDollars(player, "cash") * 100) } } or Failure("player_not_found")
end

function Banking.TransactAtm(controller, definition, data)
	if ProviderName() ~= "qb" then return Result("TransactAtm", controller, definition, data) end
	local player = QBPlayer(controller)
	if not player then return Failure("player_not_found") end
	data = type(data) == "table" and data or {}
	local amount = math.max(0, math.floor(tonumber(data.amountPence or data.amount) or 0))
	if amount <= 0 then return Failure("invalid_amount") end
	local operation = tostring(data.operation or "")
	if operation == "withdraw" then
		local result = QBMoneyResult(player, amount, false, "ATM withdrawal")
		if not result.ok then return result end
		if not SetMoney(player, "cash", MoneyDollars(player, "cash") + amount / 100) then QBMoneyResult(player, amount, true, "ATM reversal") return Failure("cash_api_unavailable") end
		result.operation, result.amountPence, result.feePence, result.chargedPence, result.netPence = operation, amount, 0, amount, amount
		result.profile = Banking.GetAtmProfile(controller, definition).profile
		return result
	elseif operation == "deposit" then
		local cash = math.floor(MoneyDollars(player, "cash") * 100)
		if cash < amount then return Failure("not_enough_cash") end
		if not SetMoney(player, "cash", (cash - amount) / 100) then return Failure("cash_api_unavailable") end
		local result = QBMoneyResult(player, amount, true, "ATM deposit")
		if not result.ok then SetMoney(player, "cash", cash / 100) return result end
		result.operation, result.amountPence, result.feePence, result.chargedPence, result.netPence = operation, amount, 0, amount, amount
		result.profile = Banking.GetAtmProfile(controller, definition).profile
		return result
	end
	return Failure("invalid_operation")
end

function Banking.NotifyPlayerDebit(controller, debitResult, amountPence, reference, extra)
	if not controller or type(debitResult) ~= "table" or debitResult.ok ~= true then return false end
	local amount = math.floor(tonumber(amountPence) or 0)
	if amount <= 0 then return false end
	extra = type(extra) == "table" and extra or {}
	local function FormatPence(value)
		local pence = math.max(0, math.floor(tonumber(value) or 0))
		return string.format("%d.%02d", math.floor(pence / 100), pence % 100)
	end
	return pcall(function()
		TriggerClientEvent(controller, "m-phone:bank:notify", { kind = "bank", code = "debited", title = tostring(extra.title or "Bank account"), message = tostring(extra.message or "Payment completed."), amount = amount, amountText = FormatPence(amount), balanceBefore = debitResult.balanceBefore, balanceBeforeText = FormatPence(debitResult.balanceBefore), balanceAfter = debitResult.balanceAfter, balanceAfterText = FormatPence(debitResult.balanceAfter), reference = tostring(reference or "Payment"), txId = tostring(debitResult.txId or ""), groupId = tostring(debitResult.groupId or "") })
	end)
end

function Banking.InstallLegacyDbBridge(database)
	if type(database) ~= "table" then return end
	database.GetBankAccount = Banking.GetAccountByPlayerId
	database.GetBankProfile = Banking.GetAccountByPlayerId
	database.GetBankAccountByAccountId = Banking.GetAccountByAccountId
	database.GetBankBalance = function(playerId) local result = Banking.GetBalanceByPlayerId(playerId) return result.ok and (tonumber(result.balancePence) or 0) or 0 end
	database.GetRecentBankTransactions = function(playerId, limit) local result = Banking.GetHistoryByPlayerId(playerId, limit) return result.ok and result.data or {} end
	database.GetRecentRecipients = function(playerId, limit) local result = Banking.GetRecentRecipientsByPlayerId(playerId, limit) return result.ok and result.data or {} end
	database.RunTransfer = function(playerId, accountId, recipientName, amount, reference, extra) return Banking.TransferByPlayerId(playerId, { recipientAccount = accountId, recipientName = recipientName, amount = amount, reference = reference, requestId = type(extra) == "table" and extra.requestId or nil, source = type(extra) == "table" and extra.source or nil }) end
	database.CreditPlayer = function(playerId, amount, transactionType, reference, extra) return Banking.CreditByPlayerId(playerId, amount, reference, extra) end
	database.DebitPlayer = function(playerId, amount, transactionType, reference, extra) return Banking.DebitByPlayerId(playerId, amount, reference, extra) end
	database.NotifyPlayerDebit = Banking.NotifyPlayerDebit
end

return Banking
