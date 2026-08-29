local Shared = require("server_shared")
local Core = _G.MPhone
if not Core then return end

local DB = Core.DB
local Reservations = {}
local ProcessedRequests = {}
local ProcessedRequestOrder = {}
local MeterLocks = {}
local MeterConfig = type(Config) == "table" and type(Config.ParkingMeter) == "table" and Config.ParkingMeter or {}
local MINUTES_STEP = math.max(1, math.floor(tonumber(MeterConfig.MinutesStep) or 15))
local MAX_MINUTES = math.max(MINUTES_STEP, math.floor(tonumber(MeterConfig.MaxMinutes) or 240))
local PRICE_PER_STEP_PENCE = math.max(0, math.floor((tonumber(MeterConfig.PricePerStep) or 15) * 100))
local MAX_PROCESSED_REQUESTS = 512

local function RememberProcessedRequest(requestKey, result)
	ProcessedRequests[requestKey] = result
	ProcessedRequestOrder[#ProcessedRequestOrder + 1] = requestKey
	if #ProcessedRequestOrder <= MAX_PROCESSED_REQUESTS then return end
	local expiredKey = table.remove(ProcessedRequestOrder, 1)
	if expiredKey then ProcessedRequests[expiredKey] = nil end
end

local function Reply(controller, requestId, result)
	result = type(result) == "table" and result or { ok = false, error = "invalid_response" }
	result.requestId = tostring(requestId or "")
	TriggerClientEvent(controller, "m-phone:parkingMeter:result", result)
end

local function PublicState(meterId)
	local reservation = Reservations[meterId]
	if not reservation then return { meterId = meterId, active = false } end
	if tonumber(reservation.expiresAt) <= os.time() then
		Reservations[meterId] = nil
		return { meterId = meterId, active = false }
	end
	return {
		meterId = meterId,
		active = true,
		expiresAt = reservation.expiresAt,
	}
end

local function ResolvePlayer(controller)
	if not controller or not exports or not exports["qb-core"] then return nil end
	local ok, player = pcall(function() return exports["qb-core"]:GetPlayer(controller) end)
	return ok and type(player) == "table" and player or nil
end

local function ResolveInventoryPlayerId(controller)
	if not exports or not exports["m-inventory"] then return "" end
	local ok, playerId = pcall(function()
		return exports["m-inventory"]:GetPlayerId(controller)
	end)
	return ok and tostring(playerId or "") or ""
end

local function ResolvePlayerName(controller)
	local player = ResolvePlayer(controller)
	local playerData = player and type(player.PlayerData) == "table" and player.PlayerData or {}
	local charInfo = type(playerData.charinfo) == "table" and playerData.charinfo or {}
	local fullName = (tostring(charInfo.firstname or "") .. " " .. tostring(charInfo.lastname or ""))
		:gsub("^%s+", "")
		:gsub("%s+$", "")
	return fullName ~= "" and fullName or tostring(playerData.name or "Parking customer")
end

local function CashBalance(controller)
	local player = ResolvePlayer(controller)
	local playerData = player and type(player.PlayerData) == "table" and player.PlayerData or {}
	local money = type(playerData.money) == "table" and playerData.money or {}
	return tonumber(money.cash) or 0
end

local function DebitCash(controller, amountDollars)
	if not exports or not exports["qb-core"] then return false, "money_api_unavailable" end
	if CashBalance(controller) < amountDollars then return false, "insufficient_cash" end
	local ok, result = pcall(function()
		return exports["qb-core"]:Player(
			controller,
			"RemoveMoney",
			"cash",
			amountDollars,
			"m-phone:parking-meter"
		)
	end)
	if not ok then return false, "money_api_failed" end
	if result ~= true then return false, "insufficient_cash" end
	pcall(function() exports["qb-core"]:Player(controller, "Save") end)
	return true
end

local function Charge(controller, playerId, amountPence, requestId, meterId)
	local account = DB and DB.GetBankAccount and DB.GetBankAccount(playerId) or nil
	if account and DB and DB.DebitPlayer then
		local debit = DB.DebitPlayer(playerId, amountPence, "parking_fee", "Parking meter", {
			system = "m-phone:parking-meter",
			origin = meterId,
			requestId = requestId,
			groupId = "parking-meter|" .. requestId,
			actorId = playerId,
			peerId = "city:parking",
			reason = "parking_fee",
			details = { meterId = meterId },
		})
		if debit and debit.ok == true then
			return true, "bank", debit
		end
		local errorCode = debit and tostring(debit.error or "") or "bank_debit_failed"
		if errorCode ~= "not_enough_money" and errorCode ~= "no_bank_account" and errorCode ~= "sender_locked" then
			return false, errorCode
		end
	end

	local cashOk, cashError = DebitCash(controller, amountPence / 100)
	if cashOk then return true, "cash", nil end
	if cashError == "insufficient_cash" then return false, "insufficient_funds" end
	return false, cashError
end

local function Refund(controller, playerId, amountPence, paymentSource, requestId, meterId)
	if paymentSource == "bank" and DB and DB.CreditPlayer then
		local result = DB.CreditPlayer(playerId, amountPence, "parking_refund", "Parking meter refund", {
			system = "m-phone:parking-meter",
			origin = meterId,
			requestId = "refund|" .. requestId,
			groupId = "parking-meter-refund|" .. requestId,
			actorId = "city:parking",
			peerId = playerId,
			reason = "parking_receipt_failed",
		}, false)
		return result and result.ok == true
	end

	if paymentSource == "cash" and exports and exports["qb-core"] then
		local ok, result = pcall(function()
			return exports["qb-core"]:Player(
				controller,
				"AddMoney",
				"cash",
				amountPence / 100,
				"m-phone:parking-meter-refund"
			)
		end)
		if ok and result == true then
			pcall(function() exports["qb-core"]:Player(controller, "Save") end)
			return true
		end
	end

	return false
end

local function CancelDocument(documentId)
	pcall(function() exports["m-documents"]:CancelDocument(documentId) end)
end

local function RemoveReceiptItem(holderId, rowUid)
	if holderId == "" or rowUid == "" then return end
	pcall(function() exports["m-inventory"]:RemoveOwnedItemByUid(holderId, rowUid) end)
end

local function ReceiptIdentity(playerId, requestId)
	local playerToken = tostring(playerId or ""):gsub("[^%w]", ""):upper():sub(-10)
	local requestToken = tostring(requestId or ""):gsub("[^%w]", ""):upper()
	if playerToken == "" then playerToken = "PLAYER" end
	if requestToken == "" then requestToken = tostring(os.time()) end
	local token = playerToken .. "-" .. requestToken
	return "parking-receipt-" .. token, "PR-" .. token:sub(-18)
end

local function FormatMoney(amountPence)
	local amount = math.max(0, math.floor(tonumber(amountPence) or 0))
	return string.format("$%d.%02d", math.floor(amount / 100), amount % 100)
end

local function FormatDateTime(timestamp)
	return os.date("%Y-%m-%d %H:%M", math.floor(tonumber(timestamp) or os.time()))
end

local function CreateReceiptDocument(context)
	local ok, created, reason = pcall(function()
		return exports["m-documents"]:CreatePendingDocument({
			id = context.documentId,
			issueRequestId = "parking-payment:" .. context.documentId,
			holderId = context.holderId,
			type = "parking_receipt",
			number = context.documentNumber,
			title = "Parking Payment Receipt",
			shortTitle = "Parking Receipt",
			tone = "transport",
			status = "pending",
			issuedBy = "Pacifica Parking Authority",
			issuedAt = os.date("%Y-%m-%d"),
			issuedAtUnix = os.time(),
			expiresAt = "No expiry",
			ownerName = context.ownerName,
			fields = {
				{ label = "Meter ID", value = context.meterId },
				{ label = "Parking purchased", value = tostring(context.minutes) .. " minutes" },
				{ label = "Amount paid", value = FormatMoney(context.pricePence) },
				{ label = "Payment method", value = context.paymentSource == "cash" and "Cash" or "Bank account" },
				{ label = "Paid at", value = FormatDateTime(os.time()) },
				{ label = "Valid until", value = FormatDateTime(context.expiresAt) },
			},
		})
	end)
	if not ok then return false, "document_service_unavailable" end
	return created == true, tostring(reason or (created == true and "ok" or "document_create_failed"))
end

local function CanIssueReceipt(holderId, controller)
	local ok, canGive, reason = pcall(function()
		return exports["m-inventory"]:CanGiveItem(holderId, "parking_receipt", {
			qty = 1,
			containerId = "player",
			controller = controller,
			noStack = true,
		})
	end)
	if not ok then return false, "inventory_unavailable" end
	if canGive ~= true then return false, tostring(reason or "receipt_item_unavailable") end
	return true
end

RegisterServerEvent("m-phone:parkingMeter:getState", function(a, b)
	local controller, payload = Shared.ResolveControllerAndPayload(a, b)
	payload = type(payload) == "table" and payload or {}
	local meterId = tostring(payload.meterId or "")
	Reply(controller, payload.requestId, { ok = true, operation = "state", meterId = meterId, state = PublicState(meterId) })
end)

RegisterServerEvent("m-phone:parkingMeter:pay", function(a, b)
	local controller, payload = Shared.ResolveControllerAndPayload(a, b)
	payload = type(payload) == "table" and payload or {}
	local requestId = tostring(payload.requestId or "")
	local meterId = tostring(payload.meterId or "")
	local minutes = math.floor(tonumber(payload.minutes) or 0)
	local playerId = tostring(Core.GetPlayerId(controller) or "")
	local inventoryPlayerId = ResolveInventoryPlayerId(controller)
	local requestKey = playerId .. "|" .. requestId

	if playerId == "" then Reply(controller, requestId, { ok = false, meterId = meterId, error = "player_not_found" }) return end
	if requestId == "" then Reply(controller, requestId, { ok = false, meterId = meterId, error = "request_id_missing" }) return end
	if ProcessedRequests[requestKey] then Reply(controller, requestId, ProcessedRequests[requestKey]) return end
	if meterId == "" then Reply(controller, requestId, { ok = false, meterId = meterId, error = "meter_id_missing" }) return end
	if minutes < MINUTES_STEP or minutes > MAX_MINUTES or minutes % MINUTES_STEP ~= 0 then
		Reply(controller, requestId, { ok = false, meterId = meterId, error = "invalid_duration" })
		return
	end
	if inventoryPlayerId == "" then
		Reply(controller, requestId, { ok = false, meterId = meterId, error = "inventory_unavailable" })
		return
	end
	local lockExpiresAt = tonumber(MeterLocks[meterId]) or 0
	if lockExpiresAt > os.time() then
		Reply(controller, requestId, { ok = false, meterId = meterId, error = "meter_busy" })
		return
	end

	MeterLocks[meterId] = os.time() + 30
	local function Finish(result)
		MeterLocks[meterId] = nil
		RememberProcessedRequest(requestKey, result)
		Reply(controller, requestId, result)
	end

	local receiptAllowed, receiptError = CanIssueReceipt(inventoryPlayerId, controller)
	if not receiptAllowed then
		Finish({ ok = false, meterId = meterId, error = receiptError })
		return
	end

	local pricePence = (minutes / MINUTES_STEP) * PRICE_PER_STEP_PENCE
	local current = Reservations[meterId]
	local startsAt = math.max(os.time(), current and tonumber(current.expiresAt) or 0)
	local expiresAt = startsAt + minutes * 60
	local documentId, documentNumber = ReceiptIdentity(playerId, requestId)
	local charged, paymentSource, debitResult = Charge(controller, playerId, pricePence, requestId, meterId)
	if not charged then
		Core.SWarn("Parking meter payment rejected", {
			playerId = playerId,
			meterId = meterId,
			minutes = minutes,
			pricePence = pricePence,
			reason = paymentSource,
		})
		Finish({ ok = false, meterId = meterId, error = paymentSource, pricePence = pricePence })
		return
	end

	local documentCreated, documentError = CreateReceiptDocument({
		documentId = documentId,
		documentNumber = documentNumber,
		requestId = requestId,
		holderId = inventoryPlayerId,
		ownerName = ResolvePlayerName(controller),
		meterId = meterId,
		minutes = minutes,
		pricePence = pricePence,
		paymentSource = paymentSource,
		expiresAt = expiresAt,
	})
	if not documentCreated then
		local refunded = Refund(controller, playerId, pricePence, paymentSource, requestId, meterId)
		Finish({ ok = false, meterId = meterId, error = refunded and documentError or "refund_failed" })
		return
	end

	local giveOk, itemGiven, itemReason, itemResult = pcall(function()
		return exports["m-inventory"]:GiveItem(inventoryPlayerId, "parking_receipt", {
			qty = 1,
			containerId = "player",
			controller = controller,
			noStack = true,
			meta = {
				documentId = documentId,
				documentType = "parking_receipt",
				documentNumber = documentNumber,
				holderId = inventoryPlayerId,
				meterId = meterId,
				expiresAt = expiresAt,
			},
		})
	end)
	if not giveOk or itemGiven ~= true then
		CancelDocument(documentId)
		local refunded = Refund(controller, playerId, pricePence, paymentSource, requestId, meterId)
		Finish({ ok = false, meterId = meterId, error = refunded and tostring(itemReason or "receipt_item_failed") or "refund_failed" })
		return
	end

	local receiptRowUid = type(itemResult) == "table" and tostring(itemResult.uid or "") or ""
	local activateOk, activated = pcall(function()
		return exports["m-documents"]:ActivateDocument(documentId)
	end)
	if not activateOk or activated ~= true then
		RemoveReceiptItem(inventoryPlayerId, receiptRowUid)
		CancelDocument(documentId)
		local refunded = Refund(controller, playerId, pricePence, paymentSource, requestId, meterId)
		Finish({ ok = false, meterId = meterId, error = refunded and "document_activation_failed" or "refund_failed" })
		return
	end

	Reservations[meterId] = { expiresAt = expiresAt }
	local result = {
		ok = true,
		operation = "payment",
		meterId = meterId,
		state = PublicState(meterId),
		paymentSource = paymentSource,
		pricePence = pricePence,
		addedMinutes = minutes,
		documentId = documentId,
		receiptIssued = true,
	}
	if paymentSource == "bank" and DB and DB.NotifyPlayerDebit then
		DB.NotifyPlayerDebit(controller, debitResult, pricePence, "Parking meter", {
			title = "Parking meter",
			message = "Parking time purchased. Receipt added to inventory.",
		})
	end
	Core.SInfo("Parking meter payment completed", {
		playerId = playerId,
		meterId = meterId,
		minutes = minutes,
		pricePence = pricePence,
		paymentSource = paymentSource,
		expiresAt = expiresAt,
		documentId = documentId,
	})
	Finish(result)
end)

Core.SInfo("Parking Meter server bridge loaded")
return { Reservations = Reservations, MeterLocks = MeterLocks }
