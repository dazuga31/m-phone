local APP_TAG = "m-phone:parking"

local function GetUI()
	return _G.MPhoneClient and _G.MPhoneClient.UI or nil
end

local function Log(level, message)
	print("[" .. APP_TAG .. "][" .. level .. "] " .. tostring(message))
end

local function RegisterHandlers()
	local UI = GetUI()
	if not UI then
		Log("error", "UI is unavailable")
		return
	end

	UI:RegisterEventHandler("parking:get-bootstrap", function(data, cb)
		TriggerServerEvent("m-phone:parking:getBootstrap", data or {})
		if cb then cb({ ok = true, pending = true }) end
	end)

	UI:RegisterEventHandler("parking:get-quote", function(data, cb)
		TriggerServerEvent("m-phone:parking:getQuote", data or {})
		if cb then cb({ ok = true, pending = true }) end
	end)

	UI:RegisterEventHandler("parking:pay", function(data, cb)
		TriggerServerEvent("m-phone:parking:pay", data or {})
		if cb then cb({ ok = true, pending = true }) end
	end)

	Log("info", "handlers registered")
end

for _, eventName in ipairs({ "bootstrap", "quote", "payment" }) do
	RegisterClientEvent("m-phone:parking:" .. eventName, function(payload)
		local UI = GetUI()
		if not UI then
			Log("warn", "cannot forward " .. eventName .. ", UI is unavailable")
			return
		end
		UI:SendEvent("parking:" .. eventName, payload or {})
	end)
end

RegisterHandlers()
