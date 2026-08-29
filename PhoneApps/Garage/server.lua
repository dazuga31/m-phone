local APP_TAG = "m-phone:garage"
local DB = _G.MPhone and _G.MPhone.DB or nil
local Shared = require("server_shared")

local function Log(level, message, extra)
	print("[" .. APP_TAG .. "][" .. level .. "] " .. tostring(message), extra or "")
end

local function ResolvePlayer(controller)
	if not exports or not exports["qb-core"] then return nil end

	local ok, player = pcall(function()
		return exports["qb-core"]:GetPlayer(controller)
	end)

	if not ok or type(player) ~= "table" or type(player.PlayerData) ~= "table" then
		return nil
	end

	return player
end

local function ResolveVehicleCatalog()
	if not exports or not exports["qb-core"] then return {} end

	local ok, vehicles = pcall(function()
		return exports["qb-core"]:GetShared("Vehicles")
	end)

	return ok and type(vehicles) == "table" and vehicles or {}
end

local function ResolveVehicleMedia(model)
	if not exports or not exports["m-vehicleshop"] then return nil end

	local ok, media = pcall(function()
		return exports["m-vehicleshop"]:GetVehicleMedia(model)
	end)

	return ok and type(media) == "table" and media or nil
end

local function ResolveGarageLabels(source)
	if not exports or not exports["m-properties"] then return {} end

	local ok, garages = pcall(function()
		local all = exports["m-properties"]:GetAllGarages()
		local available = exports["m-properties"]:GetAvailableGarages(source)
		for _, garage in pairs(available or {}) do all[#all + 1] = garage end
		return all
	end)
	if not ok or type(garages) ~= "table" then return {} end

	local labels = {}
	for _, garage in pairs(garages) do
		if type(garage) == "table" then
			local id = tostring(garage.id or "")
			if id ~= "" then labels[id] = tostring(garage.label or id) end
		end
	end
	return labels
end

local function LoadOwnedVehicles(citizenId, source)
	local ok, rows = pcall(function()
		return exports["qb-core"]:DatabaseAction(
			"Select",
			[[SELECT id, vehicle, plate, fakeplate, garage, fuel, engine, body, state,
				depotprice, drivingdistance, status, balance, paymentamount, paymentsleft, financetime
			FROM player_vehicles WHERE citizenid = ? ORDER BY id DESC]],
			{ citizenId }
		)
	end)

	if not ok or rows == nil or not DB then
		return nil, "vehicle_query_failed"
	end

	local catalog = ResolveVehicleCatalog()
	local garageLabels = ResolveGarageLabels(source)
	local vehicles = {}

	for index = 1, DB.RowsCount(rows) do
		local row = DB.RowAt(rows, index)
		if row then
			local model = tostring(DB.RowGet(row, "vehicle") or "")
			local definition = type(catalog[model]) == "table" and catalog[model] or {}
			local brand = tostring(definition.brand or "")
			local modelLabel = tostring(definition.label or model ~= "" and model or "Vehicle")
			local displayName = brand ~= "" and (brand .. " " .. modelLabel) or modelLabel
			local media = ResolveVehicleMedia(model)

			vehicles[#vehicles + 1] = {
				id = tostring(DB.RowGet(row, "id") or DB.RowGet(row, "plate") or model),
				model = model,
				label = modelLabel,
				brand = brand,
				displayName = displayName,
				category = tostring(definition.category or "vehicle"),
				image = media and tostring(media.image or "") or nil,
				imageUrl = media and tostring(media.imageUrl or "") or nil,
				brandImage = media and tostring(media.brandImage or "") or nil,
				brandImageUrl = media and tostring(media.brandImageUrl or "") or nil,
				plate = tostring(DB.RowGet(row, "plate") or "N/A"),
				fakePlate = DB.RowGet(row, "fakeplate") ~= nil and tostring(DB.RowGet(row, "fakeplate")) or nil,
				garageId = tostring(DB.RowGet(row, "garage") or ""),
				garage = garageLabels[tostring(DB.RowGet(row, "garage") or "")] or tostring(DB.RowGet(row, "garage") or "Unknown garage"),
				state = tonumber(DB.RowGet(row, "state") or 0) or 0,
				fuel = tonumber(DB.RowGet(row, "fuel") or 0) or 0,
				engine = tonumber(DB.RowGet(row, "engine") or 0) or 0,
				body = tonumber(DB.RowGet(row, "body") or 0) or 0,
				distance = tonumber(DB.RowGet(row, "drivingdistance") or 0) or 0,
				depotPrice = tonumber(DB.RowGet(row, "depotprice") or 0) or 0,
				status = DB.RowGet(row, "status") ~= nil and tostring(DB.RowGet(row, "status")) or nil,
				finance = {
					balance = tonumber(DB.RowGet(row, "balance") or 0) or 0,
					paymentAmount = tonumber(DB.RowGet(row, "paymentamount") or 0) or 0,
					paymentsLeft = tonumber(DB.RowGet(row, "paymentsleft") or 0) or 0,
					financeTime = tonumber(DB.RowGet(row, "financetime") or 0) or 0,
				},
			}
		end
	end

	return vehicles, nil
end

RegisterServerEvent("m-phone:garage:getVehicles", function(a, b)
	local source = Shared.ResolveControllerAndPayload(a, b)
	local player = ResolvePlayer(source)
	if not player then
		TriggerClientEvent(source, "m-phone:garage:data", {
			ok = false,
			error = "player_not_found",
			vehicles = {},
		})
		return
	end

	local citizenId = tostring(player.PlayerData.citizenid or "")
	if citizenId == "" then
		TriggerClientEvent(source, "m-phone:garage:data", {
			ok = false,
			error = "citizen_not_found",
			vehicles = {},
		})
		return
	end

	local vehicles, errorCode = LoadOwnedVehicles(citizenId, source)
	local success = vehicles ~= nil

	Log("info", "vehicle list requested", {
		citizenId = citizenId,
		count = success and #vehicles or 0,
		ok = success,
	})

	TriggerClientEvent(source, "m-phone:garage:data", {
		ok = success,
		error = errorCode,
		vehicles = vehicles or {},
	})
end)

Log("info", "Garage server module loaded")
