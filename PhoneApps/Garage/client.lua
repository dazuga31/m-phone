local APP_TAG = "m-phone:garage"

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

	UI:RegisterEventHandler("garage:get-vehicles", function(data, cb)
		TriggerServerEvent("m-phone:garage:getVehicles", data or {})

		if cb then
			cb({ ok = true, pending = true })
		end
	end)

	Log("info", "handlers registered")
end

RegisterClientEvent("m-phone:garage:data", function(payload)
	local UI = GetUI()
	if not UI then
		Log("warn", "cannot forward garage data, UI is unavailable")
		return
	end

	UI:SendEvent("garage:data", payload or {})
end)

RegisterHandlers()
