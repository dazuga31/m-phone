local Shared = require("server_shared")
local Core = _G.MPhone

if not Core then
	print("[m-phone][KioskApp][error] Core (_G.MPhone) not found")
	return
end

local Business = Core.Business

local function Reply(controller, requestId, result, callError)
	result = type(result) == "table" and result or {
		ok = false,
		error = tostring(callError or "business_unavailable"),
	}
	TriggerClientEvent(controller, "m-phone:kioskPayResult", {
		requestId = tostring(requestId or ""),
		ok = result.ok == true,
		reason = tostring(result.error or (result.ok == true and "ok" or "kiosk_checkout_failed")),
		extra = result.data,
	})
end

RegisterServerEvent("m-phone:kioskPay", function(a, b)
	local controller, payload = Shared.ResolveControllerAndPayload(a, b)
	payload = type(payload) == "table" and payload or {}
	if not Business or type(Business.KioskCheckout) ~= "function" then
		Reply(controller, payload.requestId, nil, "business_unavailable")
		return
	end
	local result, callError = Business.KioskCheckout(controller, payload)
	Reply(controller, payload.requestId, result, callError)
end)

Core.SInfo("KioskApp presentation adapter loaded", {
	backend = "m-business",
})
