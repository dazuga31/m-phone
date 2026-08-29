local function Apply(DB)
	local function EnsureReady()
		if DB and DB.Init then DB.Init() end
	end

	local RowsCount = DB.RowsCount
	local RowAt = DB.RowAt

	local function MapRow(row)
		if not row then return nil end
		return {
			id = tostring(DB.RowGet(row, "ID") or ""),
			requestId = tostring(DB.RowGet(row, "RequestID") or ""),
			playerId = tostring(DB.RowGet(row, "PlayerID") or ""),
			citizenId = tostring(DB.RowGet(row, "CitizenID") or ""),
			zoneId = tostring(DB.RowGet(row, "ZoneID") or ""),
			zoneLabel = tostring(DB.RowGet(row, "ZoneLabel") or ""),
			plate = tostring(DB.RowGet(row, "Plate") or ""),
			startsAt = tonumber(DB.RowGet(row, "StartsAt") or 0) or 0,
			expiresAt = tonumber(DB.RowGet(row, "ExpiresAt") or 0) or 0,
			minutes = tonumber(DB.RowGet(row, "Minutes") or 0) or 0,
			basePrice = tonumber(DB.RowGet(row, "BasePrice") or 0) or 0,
			weekendDiscount = tonumber(DB.RowGet(row, "WeekendDiscount") or 0) or 0,
			peakFee = tonumber(DB.RowGet(row, "PeakFee") or 0) or 0,
			totalPrice = tonumber(DB.RowGet(row, "TotalPrice") or 0) or 0,
			status = tostring(DB.RowGet(row, "Status") or "active"),
			createdAt = tonumber(DB.RowGet(row, "CreatedAt") or 0) or 0,
		}
	end

	DB.Parking = DB.Parking or {}

	function DB.Parking.ExpireOld(now)
		EnsureReady()
		return Database.Execute(
			"UPDATE ParkingSessions SET Status = 'expired' WHERE Status = 'active' AND ExpiresAt <= ?",
			{ math.floor(tonumber(now) or os.time()) }
		) == true
	end

	function DB.Parking.GetByRequestId(requestId)
		EnsureReady()
		local rows = Database.Select([[SELECT * FROM ParkingSessions WHERE RequestID = ? LIMIT 1]], {
			tostring(requestId or ""),
		})
		return MapRow(RowAt(rows, 1))
	end

	function DB.Parking.GetActiveByPlate(plate, now)
		EnsureReady()
		local rows = Database.Select([[
			SELECT * FROM ParkingSessions
			WHERE Plate = ? AND Status = 'active' AND ExpiresAt > ?
			ORDER BY ExpiresAt DESC LIMIT 1
		]], { tostring(plate or ""), math.floor(tonumber(now) or os.time()) })
		return MapRow(RowAt(rows, 1))
	end

	function DB.Parking.ListActive(playerId, now)
		EnsureReady()
		local rows = Database.Select([[
			SELECT * FROM ParkingSessions
			WHERE PlayerID = ? AND Status = 'active' AND ExpiresAt > ?
			ORDER BY ExpiresAt DESC
		]], { tostring(playerId or ""), math.floor(tonumber(now) or os.time()) })
		local result, seen = {}, {}
		for index = 1, RowsCount(rows) do
			local session = MapRow(RowAt(rows, index))
			if session and not seen[session.plate] then
				seen[session.plate] = true
				result[#result + 1] = session
			end
		end
		return result
	end

	function DB.Parking.Create(session)
		EnsureReady()
		session = type(session) == "table" and session or {}
		return Database.Execute([[
			INSERT INTO ParkingSessions (
				ID, RequestID, PlayerID, CitizenID, ZoneID, ZoneLabel, Plate,
				StartsAt, ExpiresAt, Minutes, BasePrice, WeekendDiscount,
				PeakFee, TotalPrice, Status, CreatedAt
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		]], {
			tostring(session.id or ""), tostring(session.requestId or ""),
			tostring(session.playerId or ""), tostring(session.citizenId or ""),
			tostring(session.zoneId or ""), tostring(session.zoneLabel or ""),
			tostring(session.plate or ""), math.floor(tonumber(session.startsAt) or 0),
			math.floor(tonumber(session.expiresAt) or 0), math.floor(tonumber(session.minutes) or 0),
			math.floor(tonumber(session.basePrice) or 0), math.floor(tonumber(session.weekendDiscount) or 0),
			math.floor(tonumber(session.peakFee) or 0), math.floor(tonumber(session.totalPrice) or 0),
			tostring(session.status or "active"), math.floor(tonumber(session.createdAt) or os.time()),
		}) == true
	end
end

return Apply
