-- m-phone/Apps/Courier/client.lua

local APP_TAG = "m-phone:courier"

local function LogInfo(msg, extra)
	if _G.MPhoneClient and _G.MPhoneClient.LogInfo then
		_G.MPhoneClient.LogInfo(msg, APP_TAG, extra)
	else
		print("[" .. APP_TAG .. "][info] " .. tostring(msg))
	end
end

local function LogWarn(msg, extra)
	if _G.MPhoneClient and _G.MPhoneClient.LogWarn then
		_G.MPhoneClient.LogWarn(msg, APP_TAG, extra)
	else
		print("[" .. APP_TAG .. "][warn] " .. tostring(msg))
	end
end

local function GetUI()
	return _G.MPhoneClient and _G.MPhoneClient.UI or nil
end

local function RegisterHandlers()
	local UI = GetUI()
	if not UI then
		print("[" .. APP_TAG .. "][error] UI is nil")
		return
	end

	UI:RegisterEventHandler("courier:get-data", function(data, cb)
		TriggerServerEvent("m-phone:courier:getData", data or {})

		if cb then
			cb({ ok = true, pending = true })
		end
	end)

	UI:RegisterEventHandler("courier:accept-job", function(data, cb)
		local jobId = data and (data.jobId or data.id) or nil

		TriggerServerEvent("m-phone:courier:acceptJob", {
			jobId = jobId,
		})

		if cb then
			cb({ ok = true, pending = true })
		end
	end)

	UI:RegisterEventHandler("courier:complete-job", function(data, cb)
		local jobId = data and (data.jobId or data.id) or nil

		TriggerServerEvent("m-phone:courier:completeJob", {
			jobId = jobId,
		})

		if cb then
			cb({ ok = true, pending = true })
		end
	end)

	UI:RegisterEventHandler("courier:cancel-job", function(data, cb)
		local jobId = data and (data.jobId or data.id) or nil

		TriggerServerEvent("m-phone:courier:cancelJob", {
			jobId = jobId,
		})

		if cb then
			cb({ ok = true, pending = true })
		end
	end)

	UI:RegisterEventHandler("courier:print-invoice", function(data, cb)
		local routeId = data and (data.routeId or data.jobId or data.id) or nil
		local requestId = ("courier_invoice_%s_%06d"):format(tostring(os.time()), math.random(0, 999999))

		TriggerServerEvent("m-phone:courier:printInvoice", {
			routeId = routeId,
			requestId = requestId,
		})

		if cb then
			cb({ ok = true, pending = true })
		end
	end)

	LogInfo("handlers registered")
end

RegisterClientEvent("m-phone:courier:data", function(payload)
	local UI = GetUI()
	if not UI then
		LogWarn("cannot forward courier:data, UI nil")
		return
	end

	UI:SendEvent("courier:data", payload)
end)

RegisterClientEvent("m-phone:courier:printResult", function(payload)
	local UI = GetUI()
	if UI then
		UI:SendEvent("courier:printResult", payload)
	end
end)

RegisterHandlers()
