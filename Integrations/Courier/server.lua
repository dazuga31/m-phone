local Courier = {}

local function ResourceName()
	return tostring(Config and Config.Courier and Config.Courier.Resource or "m-courier")
end

local function Call(methodName, ...)
	if not exports then return nil, "courier_unavailable" end
	local okProvider, provider = pcall(function() return exports[ResourceName()] end)
	if not okProvider or not provider then return nil, "courier_unavailable" end
	local okMethod, method = pcall(function() return provider[methodName] end)
	if not okMethod or method == nil then
		return nil, "courier_export_missing:" .. tostring(methodName)
	end
	local ok, first, second, third = pcall(method, provider, ...)
	if not ok then return nil, tostring(first) end
	return first, second, third
end

function Courier.IsReady()
	return Call("IsReady") == true
end

function Courier.GetData(controller)
	local result, errorCode = Call("GetData", controller)
	if type(result) ~= "table" then return { ok = false, error = tostring(errorCode or "courier_unavailable") } end
	return result
end

function Courier.AcceptJob(controller, data)
	local result, errorCode = Call("AcceptJob", controller, data)
	if type(result) ~= "table" then return { ok = false, error = tostring(errorCode or "courier_unavailable") } end
	return result
end

function Courier.CompleteJob(controller, data)
	local result, errorCode = Call("CompleteJob", controller, data)
	if type(result) ~= "table" then return { ok = false, error = tostring(errorCode or "courier_unavailable") } end
	return result
end

function Courier.CancelJob(controller, data)
	local result, errorCode = Call("CancelJob", controller, data)
	if type(result) ~= "table" then return { ok = false, error = tostring(errorCode or "courier_unavailable") } end
	return result
end

function Courier.PrintInvoice(controller, data)
	local result, errorCode = Call("PrintInvoice", controller, data)
	if type(result) ~= "table" then return { ok = false, error = tostring(errorCode or "courier_unavailable") } end
	return result
end

function Courier.GetDataForPlayer(playerId)
	return Call("GetDataForPlayer", playerId)
end

function Courier.GetProfileForPlayer(playerId)
	return Call("GetProfileForPlayer", playerId)
end

function Courier.GetActiveJobForPlayer(playerId)
	return Call("GetActiveJobForPlayer", playerId)
end

return Courier
