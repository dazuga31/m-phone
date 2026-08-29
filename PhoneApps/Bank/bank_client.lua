local Core = _G.MPhoneClient
if not Core or not Core.UI then
	print("[m-phone][BankApp][error] _G.MPhoneClient (or UI) not found")
	return
end

local UI = Core.UI
local Shared = require("PhoneApps.Bank.bank_client_shared")
local requestSequence = 0

local function ResolveArgs(data, cb)
	if type(data) == "function" and cb == nil then return {}, data end
	return type(data) == "table" and data or {}, cb
end

local function ResolveRequestId(data)
	local requestId = tostring(type(data) == "table" and data.requestId or "")
	if requestId ~= "" then return requestId end
	requestSequence = requestSequence + 1
	return Shared.NextReqId(requestSequence)
end

local function SendResult(requestId, ok, error, extra)
	local payload = type(extra) == "table" and extra or {}
	payload.requestId = tostring(requestId or "")
	payload.ok = ok == true
	payload.error = error
	UI:SendEvent("bank:result", payload)
end

RegisterClientEvent("m-phone:bankResult", function(payload)
	local requestId = tostring(payload and payload.requestId or "")
	Core.LogDbg("bankResult <- server", "m-phone", {
		requestId = requestId,
		ok = payload and payload.ok == true,
		error = payload and payload.error or nil,
	})

	if requestId == "" then
		Core.LogWarn("bankResult <- server (missing requestId)", "m-phone", { payload = payload })
		return
	end

	UI:SendEvent("bank:result", payload)
	if payload and payload.ok == true and payload.kind == "bankFundBusiness" and Core.PushInitialData then
		Core.PushInitialData()
	end
end)

UI:RegisterEventHandler("bankGetProfile", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	Core.LogDbg("bankGetProfile -> server", "m-phone", { requestId = requestId })
	TriggerServerEvent("m-phone:bankGetProfile", { requestId = requestId })
end)

UI:RegisterEventHandler("bankCreateAccount", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	local planId = tostring(data.planId or "")
	if planId == "" then
		SendResult(requestId, false, "invalid_planId")
		return
	end

	TriggerServerEvent("m-phone:bankCreateAccount", {
		requestId = requestId,
		planId = planId,
		holderName = tostring(data.holderName or ""),
		designBgUrl = data.designBgUrl,
	})
end)

UI:RegisterEventHandler("bankGetRecents", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	TriggerServerEvent("m-phone:bankGetRecents", {
		requestId = requestId,
		limit = tonumber(data.limit) or 10,
	})
end)

UI:RegisterEventHandler("bankGetHistory", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	TriggerServerEvent("m-phone:bankGetHistory", {
		requestId = requestId,
		limit = tonumber(data.limit) or 20,
	})
end)

UI:RegisterEventHandler("bankValidateRecipient", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	local recipientAccount = tostring(data.recipientAccount or "")
	if recipientAccount == "" or #recipientAccount < 6 then
		SendResult(requestId, false, "invalid_recipient_account")
		return
	end

	TriggerServerEvent("m-phone:bankValidateRecipient", {
		requestId = requestId,
		recipientAccount = recipientAccount,
	})
end)

UI:RegisterEventHandler("bankTransfer", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	local recipientAccount = tostring(data.recipientAccount or "")
	local recipientName = tostring(data.recipientName or "")
	local amount = math.floor((tonumber(data.amount) or 0) + 0.0)
	local reference = tostring(data.reference or "")

	if recipientAccount == "" or #recipientAccount < 6 then
		SendResult(requestId, false, "invalid_recipient_account")
		return
	end
	if recipientName == "" or #recipientName < 3 then
		SendResult(requestId, false, "invalid_recipient_name")
		return
	end
	if amount <= 0 then
		SendResult(requestId, false, "invalid_amount")
		return
	end
	if reference == "" or #reference < 2 then
		SendResult(requestId, false, "invalid_reference")
		return
	end

	TriggerServerEvent("m-phone:bankTransfer", {
		requestId = requestId,
		recipientAccount = recipientAccount,
		recipientName = recipientName,
		amount = amount,
		reference = reference,
	})
end)

UI:RegisterEventHandler("bankPing", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	TriggerServerEvent("m-phone:bankPing", {
		requestId = requestId,
		clientMs = tonumber(data.clientMs) or Shared.NowMs(),
	})
end)

UI:RegisterEventHandler("bankFundBusiness", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	TriggerServerEvent("m-phone:bankFundBusiness", {
		requestId = requestId,
		shopId = tostring(data.shopId or ""),
		amountPence = math.floor(tonumber(data.amountPence) or 0),
	})
end)

Core.LogInfo("BankApp bank_client loaded", "m-phone")
