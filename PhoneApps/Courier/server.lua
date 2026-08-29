local Courier = require("Integrations.Courier.server")
local Shared = require("server_shared")

local APP_TAG = "m-phone:courier"

local function Log(level, message, extra)
	local suffix = ""
	if type(extra) == "table" then
		local parts = {}
		for key, value in pairs(extra) do parts[#parts + 1] = tostring(key) .. "=" .. tostring(value) end
		suffix = " {" .. table.concat(parts, ", ") .. "}"
	elseif extra ~= nil then
		suffix = " " .. tostring(extra)
	end
	print("[" .. APP_TAG .. "][" .. tostring(level) .. "] " .. tostring(message) .. suffix)
end

local function PushCourierData(controller)
	local payload = Courier.GetData(controller)
	TriggerClientEvent(controller, "m-phone:courier:data", payload)
	return payload
end

RegisterServerEvent("m-phone:courier:getData", function(a, b)
	local controller = Shared.ResolveControllerAndPayload(a, b)
	local payload = PushCourierData(controller)
	Log("info", "data requested", {
		ok = payload.ok == true,
		jobs = type(payload.jobs) == "table" and #payload.jobs or 0,
		hasActiveJob = payload.activeJob ~= nil,
	})
end)

RegisterServerEvent("m-phone:courier:acceptJob", function(a, b)
	local controller, data = Shared.ResolveControllerAndPayload(a, b)
	local result = Courier.AcceptJob(controller, data)
	Log(result.ok == true and "info" or "warn", "accept job", {
		ok = result.ok == true,
		error = result.error,
		jobId = result.jobId,
	})
	PushCourierData(controller)
end)

RegisterServerEvent("m-phone:courier:completeJob", function(a, b)
	local controller, data = Shared.ResolveControllerAndPayload(a, b)
	local result = Courier.CompleteJob(controller, data)
	Log(result.ok == true and "info" or "warn", "complete job", {
		ok = result.ok == true,
		error = result.error,
		jobId = result.jobId,
	})
	PushCourierData(controller)
end)

RegisterServerEvent("m-phone:courier:cancelJob", function(a, b)
	local controller, data = Shared.ResolveControllerAndPayload(a, b)
	local result = Courier.CancelJob(controller, data)
	Log(result.ok == true and "info" or "warn", "cancel job", {
		ok = result.ok == true,
		error = result.error,
		jobId = result.jobId,
	})
	PushCourierData(controller)
end)

RegisterServerEvent("m-phone:courier:printInvoice", function(a, b)
	local controller, data = Shared.ResolveControllerAndPayload(a, b)
	local result = Courier.PrintInvoice(controller, data)
	TriggerClientEvent(controller, "m-phone:courier:printResult", result)
	Log(result.ok == true and "info" or "warn", "print invoice", {
		ok = result.ok == true,
		error = result.error,
		routeId = result.routeId,
	})
end)

Log("info", "Courier presentation adapter loaded", { ready = Courier.IsReady() })
