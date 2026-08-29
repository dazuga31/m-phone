local Jobs = {}

local function ResourceName()
	return tostring(Config and Config.Jobs and Config.Jobs.Resource or "m-jobs")
end

local function Call(methodName, ...)
	if not exports then return nil, "jobs_unavailable" end
	local okProvider, provider = pcall(function() return exports[ResourceName()] end)
	if not okProvider or not provider then return nil, "jobs_unavailable" end
	local okMethod, method = pcall(function() return provider[methodName] end)
	if not okMethod or method == nil then
		return nil, "jobs_export_missing:" .. tostring(methodName)
	end
	local ok, first, second, third = pcall(method, provider, ...)
	if not ok then return nil, tostring(first) end
	return first, second, third
end

local function Result(methodName, ...)
	local result, errorCode = Call(methodName, ...)
	if type(result) ~= "table" then
		return { ok = false, error = tostring(errorCode or "jobs_unavailable") }
	end
	return result
end

function Jobs.IsReady()
	return Call("IsReady") == true
end

function Jobs.GetApplicationProfile(controller)
	return Result("GetApplicationProfile", controller)
end

function Jobs.SubmitApplication(controller, payload)
	return Result("SubmitApplication", controller, payload)
end

function Jobs.GetLatestApplicationByPlayer(playerId)
	return Call("GetLatestApplicationByPlayer", playerId)
end

return Jobs
