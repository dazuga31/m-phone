local Core = _G.MPhoneClient
if not Core or not Core.UI then
	print("[m-phone][KioskApp][error] _G.MPhoneClient (or UI) not found")
	return
end

local UI = Core.UI
local Shared = require("PosApps.Kiosk.kiosk_client_shared")
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

local function SendResult(requestId, ok, reason, extra)
	UI:SendEvent("kiosk:result", {
		requestId = tostring(requestId or ""),
		ok = ok == true,
		reason = tostring(reason or ""),
		extra = extra,
	})
end

RegisterClientEvent("m-phone:kioskPayResult", function(payload)
	if type(payload) ~= "table" then
		Core.LogErr("kioskPayResult: invalid payload", "m-phone", { payload = payload })
		return
	end
	if tostring(payload.requestId or "") == "" then
		Core.LogWarn("kioskPayResult: missing requestId", "m-phone", { payload = payload })
		return
	end
	UI:SendEvent("kiosk:result", payload)
end)

UI:RegisterEventHandler("kioskPay", function(data, cb)
	data = ResolveArgs(data, cb)
	local requestId = ResolveRequestId(data)
	local items = type(data.items) == "table" and data.items or {}
	if #items == 0 then
		SendResult(requestId, false, "empty_cart")
		return
	end

	TriggerServerEvent("m-phone:kioskPay", {
		requestId = requestId,
		shopId = tostring(data.shopId or "default"),
		method = tostring(data.method or "cash"),
		total = tonumber(data.total) or 0,
		totalPence = tonumber(data.totalPence),
		vatRate = tonumber(data.vatRate),
		pricesIncludeVat = data.pricesIncludeVat == true,
		items = items,
	})
end)

Core.LogInfo("KioskApp kiosk_client loaded", "m-phone")
