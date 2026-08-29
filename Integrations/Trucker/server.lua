local Trucker = {}

local function ResourceName()
	return tostring(Config and Config.Trucker and Config.Trucker.Resource or "m-trucker")
end

local function Call(methodName, ...)
	if not exports then return nil, "trucker_unavailable" end
	local okProvider, provider = pcall(function() return exports[ResourceName()] end)
	if not okProvider or not provider then return nil, "trucker_unavailable" end
	local okMethod, method = pcall(function() return provider[methodName] end)
	if not okMethod or method == nil then
		return nil, "trucker_export_missing:" .. tostring(methodName)
	end
	local ok, first, second, third = pcall(method, provider, ...)
	if not ok then return nil, tostring(first) end
	return first, second, third
end

function Trucker.IsReady()
	return Call("IsReady") == true
end

function Trucker.EnsureProfileForPlayer(playerId)
	return Call("EnsureProfileForPlayer", playerId)
end

function Trucker.GetOrdersForPlayer(playerId, limit, depotId)
	local result = Call("GetOrdersForPlayer", playerId, limit, depotId)
	return type(result) == "table" and result or {}
end

function Trucker.GetProfileForPlayer(playerId)
	return Call("GetProfileForPlayer", playerId)
end

function Trucker.GetActiveRouteForPlayer(playerId)
	return Call("GetActiveRouteForPlayer", playerId)
end

function Trucker.CreateSupplyOrder(data)
	return Call("CreateSupplyOrder", data)
end

function Trucker.DeleteSupplyOrder(orderId)
	return Call("DeleteSupplyOrder", orderId)
end

Trucker.EnsureTruckerProfileForPlayer = Trucker.EnsureProfileForPlayer
Trucker.GetTruckerOrdersForPlayer = Trucker.GetOrdersForPlayer
Trucker.GetTruckerProfileForPlayer = Trucker.GetProfileForPlayer
Trucker.GetTruckerActiveRouteForPlayer = Trucker.GetActiveRouteForPlayer

return Trucker
