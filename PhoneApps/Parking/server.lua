local APP_TAG = "m-phone:parking"
local Locks = {}
local Core = _G.MPhone or {}
local DB = Core.DB
local Shared = require("server_shared")

if not DB then
	print("[" .. APP_TAG .. "][error] database unavailable")
	return
end

local function Log(level, message, extra)
	print("[" .. APP_TAG .. "][" .. level .. "] " .. tostring(message), extra or "")
end

local function Reply(source, eventName, payload)
	TriggerClientEvent(source, "m-phone:parking:" .. eventName, payload or {})
end

local function ResolvePlayer(controller)
	if not exports or not exports["qb-core"] then return nil end
	local ok, player = pcall(function()
		return exports["qb-core"]:GetPlayer(controller)
	end)
	if not ok or type(player) ~= "table" or type(player.PlayerData) ~= "table" then return nil end
	return player
end

local function ResolvePlayerId(controller)
	if Core.GetPlayerId then
		local ok, playerId = pcall(Core.GetPlayerId, controller)
		if ok and tostring(playerId or "") ~= "" then return tostring(playerId) end
	end
	return ""
end

local function NormalizeZoneId(value)
	local digits = tostring(value or ""):gsub("%D", "")
	if digits == "" or #digits > 4 then return "" end
	return string.format("%04d", tonumber(digits) or 0)
end

local function NormalizePlate(value)
	return tostring(value or ""):upper():gsub("[^A-Z0-9]", ""):sub(1, 12)
end

local function DisplayPlate(value)
	return tostring(value or ""):upper():gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 14)
end

local function GetZone(zoneId)
	local zones = Config and Config.ParkingApp and Config.ParkingApp.Zones or {}
	return type(zones) == "table" and zones[zoneId] or nil
end

local function PublicZone(zoneId, zone)
	return {
		id = zoneId,
		label = tostring(zone.label or ("Zone " .. zoneId)),
		district = tostring(zone.district or "Pacifica"),
		pricePer15 = math.max(0, math.floor(tonumber(zone.pricePer15) or 0)),
		weekendDiscount = math.max(0, math.floor(tonumber(zone.weekendDiscount) or 0)),
		peakFee = math.max(0, math.floor(tonumber(zone.peakFee) or 0)),
		maxMinutes = math.max(15, math.floor(tonumber(zone.maxMinutes) or tonumber(Config.ParkingApp.MaxMinutes) or 480)),
		free = zone.free == true or (tonumber(zone.pricePer15) or 0) <= 0,
	}
end

local function DayIncluded(days, day)
	for _, value in ipairs(type(days) == "table" and days or {}) do
		if tonumber(value) == day then return true end
	end
	return false
end

local function IsPeak(timestamp, zone)
	local clock = os.date("*t", timestamp)
	local minute = (tonumber(clock.hour) or 0) * 60 + (tonumber(clock.min) or 0)
	local periods = type(zone.peakPeriods) == "table" and zone.peakPeriods
		or (Config.ParkingApp and Config.ParkingApp.PeakPeriods) or {}
	for _, period in ipairs(periods) do
		if DayIncluded(period.days, clock.wday)
			and minute >= (tonumber(period.startMinute) or 0)
			and minute < (tonumber(period.endMinute) or 0) then
			return true
		end
	end
	return false
end

local function LoadOwnedVehicles(citizenId)
	local ok, rows = pcall(function()
		return exports["qb-core"]:DatabaseAction(
			"Select",
			"SELECT id, vehicle, plate FROM player_vehicles WHERE citizenid = ? ORDER BY id DESC",
			{ citizenId }
		)
	end)
	if not ok or rows == nil then return nil, "vehicle_query_failed" end

	local vehicles = {}
	for index = 1, DB.RowsCount(rows) do
		local row = DB.RowAt(rows, index)
		local plate = DisplayPlate(DB.RowGet(row, "plate"))
		if NormalizePlate(plate) ~= "" then
			vehicles[#vehicles + 1] = {
				id = tostring(DB.RowGet(row, "id") or plate),
				plate = plate,
				model = tostring(DB.RowGet(row, "vehicle") or "Vehicle"),
			}
		end
	end
	return vehicles, nil
end

local function FindOwnedVehicle(vehicles, plate)
	local target = NormalizePlate(plate)
	for _, vehicle in ipairs(vehicles or {}) do
		if NormalizePlate(vehicle.plate) == target then return vehicle end
	end
	return nil
end

local function BankPayload(playerId)
	local account = DB.GetBankAccount(playerId)
	if not account then return { exists = false, balance = 0 } end
	return {
		exists = true,
		accountId = tostring(DB.RowGet(account, "AccountId") or ""),
		balance = tonumber(DB.RowGet(account, "Balance") or 0) or 0,
		status = tostring(DB.RowGet(account, "CardStatus") or "active"),
	}
end

local function ResolveContext(source)
	local player = ResolvePlayer(source)
	if not player then return nil, "player_not_found" end
	local playerId = ResolvePlayerId(source)
	local citizenId = tostring(player.PlayerData.citizenid or "")
	if playerId == "" then return nil, "player_id_not_found" end
	if citizenId == "" then return nil, "citizen_not_found" end
	local vehicles, vehicleError = LoadOwnedVehicles(citizenId)
	if not vehicles then return nil, vehicleError end
	return {
		player = player,
		playerId = playerId,
		citizenId = citizenId,
		vehicles = vehicles,
		bank = BankPayload(playerId),
	}, nil
end

local function BuildQuote(context, data)
	data = type(data) == "table" and data or {}
	local zoneId = NormalizeZoneId(data.zoneId)
	local zone = GetZone(zoneId)
	if not zone then return nil, "zone_not_found" end

	local vehicle = FindOwnedVehicle(context.vehicles, data.plate)
	if not vehicle then return nil, "vehicle_not_owned" end
	if context.bank.exists ~= true then return nil, "no_bank_account" end

	local publicZone = PublicZone(zoneId, zone)
	local step = math.max(1, math.floor(tonumber(Config.ParkingApp.MinutesStep) or 15))
	local requested = math.floor(tonumber(data.minutes) or tonumber(Config.ParkingApp.DefaultMinutes) or 30)
	local minutes = math.max(step, math.min(publicZone.maxMinutes, math.ceil(requested / step) * step))
	local now = os.time()
	DB.Parking.ExpireOld(now)
	local active = DB.Parking.GetActiveByPlate(NormalizePlate(vehicle.plate), now)
	if active and active.zoneId ~= zoneId then return nil, "vehicle_parked_in_other_zone" end

	local startsAt = active and active.expiresAt or now
	local basePrice = publicZone.free and 0 or math.floor((minutes / step) * publicZone.pricePer15)
	local clock = os.date("*t", now)
	local weekend = clock.wday == 1 or clock.wday == 7
	local peak = IsPeak(now, zone)
	local discount = weekend and math.floor(basePrice * publicZone.weekendDiscount / 100) or 0
	local discounted = math.max(0, basePrice - discount)
	local peakFee = peak and math.floor(discounted * publicZone.peakFee / 100) or 0
	local total = publicZone.free and 0 or discounted + peakFee

	return {
		zone = publicZone,
		plate = DisplayPlate(vehicle.plate),
		plateKey = NormalizePlate(vehicle.plate),
		vehicle = vehicle,
		minutes = minutes,
		startsAt = startsAt,
		expiresAt = startsAt + minutes * 60,
		basePrice = basePrice,
		weekendDiscount = discount,
		peakFee = peakFee,
		totalPrice = total,
		isWeekend = weekend,
		isPeak = peak,
		isExtension = active ~= nil,
	}, nil
end

RegisterServerEvent("m-phone:parking:getBootstrap", function(a, b)
	local source, data = Shared.ResolveControllerAndPayload(a, b)
	local requestId = tostring(type(data) == "table" and data.requestId or "")
	local context, errorCode = ResolveContext(source)
	if not context then
		Reply(source, "bootstrap", { ok = false, requestId = requestId, error = errorCode })
		return
	end
	local now = os.time()
	DB.Parking.ExpireOld(now)
	Reply(source, "bootstrap", {
		ok = true,
		requestId = requestId,
		bank = context.bank,
		vehicles = context.vehicles,
		activeSessions = DB.Parking.ListActive(context.playerId, now),
		minutesStep = tonumber(Config.ParkingApp.MinutesStep) or 15,
		defaultMinutes = tonumber(Config.ParkingApp.DefaultMinutes) or 30,
	})
end)

RegisterServerEvent("m-phone:parking:getQuote", function(a, b)
	local source, data = Shared.ResolveControllerAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local requestId = tostring(data.requestId or "")
	local context, errorCode = ResolveContext(source)
	if not context then
		Reply(source, "quote", { ok = false, requestId = requestId, error = errorCode })
		return
	end
	local quote, quoteError = BuildQuote(context, data)
	Reply(source, "quote", {
		ok = quote ~= nil,
		requestId = requestId,
		error = quoteError,
		quote = quote,
		bank = context.bank,
	})
end)

RegisterServerEvent("m-phone:parking:pay", function(a, b)
	local source, data = Shared.ResolveControllerAndPayload(a, b)
	data = type(data) == "table" and data or {}
	local requestId = tostring(data.requestId or ""):sub(1, 96)
	if requestId == "" then
		Reply(source, "payment", { ok = false, error = "request_id_required" })
		return
	end
	if Locks[source] then
		Reply(source, "payment", { ok = false, requestId = requestId, error = "payment_in_progress" })
		return
	end
	Locks[source] = true

	local ok, failure = xpcall(function()
		local existing = DB.Parking.GetByRequestId(requestId)
		if existing then
			Reply(source, "payment", { ok = true, requestId = requestId, session = existing, duplicate = true })
			return
		end

		local context, contextError = ResolveContext(source)
		if not context then
			Reply(source, "payment", { ok = false, requestId = requestId, error = contextError })
			return
		end
		local quote, quoteError = BuildQuote(context, data)
		if not quote then
			Reply(source, "payment", { ok = false, requestId = requestId, error = quoteError })
			return
		end

		local debit = { ok = true, balanceBefore = context.bank.balance, balanceAfter = context.bank.balance }
		if quote.totalPrice > 0 then
			debit = DB.DebitPlayer(
				context.playerId,
				quote.totalPrice,
				"parking_payment",
				"Parking zone " .. quote.zone.id,
				{
					requestId = requestId,
					source = "parking_app",
					system = "m-phone",
					reason = "parking",
					details = { zoneId = quote.zone.id, plate = quote.plate, minutes = quote.minutes },
				}
			)
			if debit.ok ~= true then
				Reply(source, "payment", { ok = false, requestId = requestId, error = debit.error, bank = BankPayload(context.playerId) })
				return
			end
		end

		local now = os.time()
		local session = {
			id = "parking_" .. tostring(now) .. "_" .. tostring(math.random(100000, 999999)),
			requestId = requestId,
			playerId = context.playerId,
			citizenId = context.citizenId,
			zoneId = quote.zone.id,
			zoneLabel = quote.zone.label,
			plate = quote.plateKey,
			startsAt = quote.startsAt,
			expiresAt = quote.expiresAt,
			minutes = quote.minutes,
			basePrice = quote.basePrice,
			weekendDiscount = quote.weekendDiscount,
			peakFee = quote.peakFee,
			totalPrice = quote.totalPrice,
			status = "active",
			createdAt = now,
		}

		if DB.Parking.Create(session) ~= true then
			if quote.totalPrice > 0 then
				DB.CreditPlayer(context.playerId, quote.totalPrice, "parking_reversal", "Parking payment reversal", {
					requestId = requestId .. ":reversal",
					source = "parking_app",
					system = "m-phone",
					reason = "parking_persistence_failed",
				}, false)
			end
			Reply(source, "payment", { ok = false, requestId = requestId, error = "parking_save_failed" })
			return
		end

		if quote.totalPrice > 0 then
			DB.NotifyPlayerDebit(source, debit, quote.totalPrice, "Parking zone " .. quote.zone.id, {
				title = "Parking paid",
				message = quote.plate .. " is covered until the selected expiry time.",
			})
		end

		session.plate = quote.plate
		Reply(source, "payment", {
			ok = true,
			requestId = requestId,
			session = session,
			bank = BankPayload(context.playerId),
		})
		Log("info", "parking session created", { zoneId = quote.zone.id, plate = quote.plate, total = quote.totalPrice })
	end, debug.traceback)

	Locks[source] = nil
	if not ok then
		Log("error", "payment handler failed", failure)
		Reply(source, "payment", { ok = false, requestId = requestId, error = "internal_error" })
	end
end)

Log("info", "Parking server module loaded")
