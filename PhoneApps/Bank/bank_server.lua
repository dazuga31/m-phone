local Shared = require("PhoneApps.Bank.bank_server_shared")

local Core = _G.MPhone
if not Core or not Core.Banking then
	print("[m-phone][bank][error] banking integration unavailable")
	return
end

local Banking = Core.Banking
local Business = Core.Business

local function NowMs()
	return Shared.NowMs()
end

local function Reply(source, requestId, kind, result, data)
	result = type(result) == "table" and result or { ok = false, error = "banking_unavailable" }
	TriggerClientEvent(source, "m-phone:bankResult", {
		requestId = tostring(requestId or ""),
		ok = result.ok == true,
		error = result.error,
		kind = kind,
		data = data,
		meta = { timestamp = NowMs() },
	})
end

RegisterServerEvent("m-phone:bankValidateRecipient", function(a, b)
	local source, data = Shared.ResolveSourceAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local result = Banking.ValidateRecipient(data.recipientAccount)
	Reply(source, data.requestId, "bankValidateRecipient", result, result.ok and {
		exists = result.exists == true,
		accountId = result.accountId,
		holderName = result.holderName,
		playerId = result.playerId,
	} or nil)
end)

RegisterServerEvent("m-phone:bankFundBusiness", function(a, b)
	local source, data = Shared.ResolveSourceAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local requestId = tostring(data.requestId or "")
	local shopId = tostring(data.shopId or "")
	local amountPence = math.floor(tonumber(data.amountPence) or 0)
	local playerId = tostring(Core.GetPlayerId(source) or "")
	if playerId == "" then Reply(source, requestId, "bankFundBusiness", { ok = false, error = "player_not_found" }) return end
	if shopId == "" or amountPence <= 0 then Reply(source, requestId, "bankFundBusiness", { ok = false, error = "invalid_amount" }) return end
	if not Business or type(Business.FundBusiness) ~= "function" then
		Reply(source, requestId, "bankFundBusiness", { ok = false, error = "business_banking_unavailable" })
		return
	end
	local result, callError = Business.FundBusiness(playerId, {
		requestId = requestId,
		shopId = shopId,
		amountPence = amountPence,
	})
	if type(result) ~= "table" then result = { ok = false, error = callError or "business_banking_unavailable" } end
	if result.ok ~= true then Reply(source, requestId, "bankFundBusiness", result) return end
	local responseData = type(result.data) == "table" and result.data or {}
	if type(responseData.banking) == "table" then
		Banking.NotifyPlayerDebit(source, responseData.banking, amountPence, "Business account deposit")
	end
	Reply(source, requestId, "bankFundBusiness", result, responseData)
end)

RegisterServerEvent("m-phone:bankGetProfile", function(a, b)
	local source, data = Shared.ResolveSourceAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local result = Banking.GetProfile(source, 20)
	Reply(source, data.requestId, "profile", result, result.profile)
end)

RegisterServerEvent("m-phone:bankCreateAccount", function(a, b)
	local source, data = Shared.ResolveSourceAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local result = Banking.CreateAccount(source, data)
	TriggerClientEvent(source, "m-phone:bankResult", {
		requestId = tostring(data.requestId or ""),
		ok = result.ok == true,
		error = result.error,
		account = result.account,
		extra = { reused = result.reused == true },
		kind = "account",
		data = result.account,
		meta = { timestamp = NowMs() },
	})
end)

RegisterServerEvent("m-phone:bankGetHistory", function(a, b)
	local source, data = Shared.ResolveSourceAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local result = Banking.GetHistory(source, tonumber(data.limit) or 20)
	Reply(source, data.requestId, "history", result, result.data or {})
end)

RegisterServerEvent("m-phone:bankGetRecents", function(a, b)
	local source, data = Shared.ResolveSourceAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local result = Banking.GetRecentRecipients(source, tonumber(data.limit) or 10)
	Reply(source, data.requestId, "recents", result, result.data or {})
end)

RegisterServerEvent("m-phone:bankTransfer", function(a, b)
	local source, data = Shared.ResolveSourceAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local result = Banking.Transfer(source, {
		requestId = data.requestId,
		recipientAccount = data.recipientAccount,
		recipientName = data.recipientName,
		amount = data.amount,
		reference = data.reference,
		source = "m-phone",
	})
	if result.ok then
		Banking.NotifyPlayerDebit(source, result, tonumber(data.amount) or 0, "Transfer: " .. tostring(data.reference or ""))
	end
	Reply(source, data.requestId, "bankTransfer", result, result.ok and {
		txId = result.txId,
		groupId = result.groupId,
		balanceBefore = result.balanceBefore,
		balanceAfter = result.balanceAfter,
	} or (result.error == "not_enough_money" and { balance = result.balance } or nil))
end)

RegisterServerEvent("m-phone:bankPing", function(a, b)
	local source, data = Shared.ResolveSourceAndPayload(a, b)
	data = type(data) == "table" and data or {}
	Reply(source, data.requestId, "bankPing", { ok = true }, {
		clientMs = tonumber(data.clientMs) or NowMs(),
		serverMs = NowMs(),
	})
end)

Core.SInfo("BankApp server module loaded", { provider = Banking.Provider() })
