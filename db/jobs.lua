local function Apply(DB)
	local function EnsureReady()
		if DB and DB.Init then
			DB.Init()
		end
	end

	local RowsCount = DB.RowsCount
	local RowAt = DB.RowAt

	local function RowsFirst(rows)
		if not rows then return nil end
		local n = RowsCount(rows)
		if n <= 0 then return nil end
		return RowAt(rows, 1)
	end

	local function Now()
		return os.time()
	end

	DB.Trucker = DB.Trucker or {}
	DB.Courier = DB.Courier or {}

	function DB.Trucker.GetProfile(playerId)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then return nil end
		local rows = Database.Select([[
			SELECT PlayerID, Name, Phone, Level, SkillsJson, UpdatedAt
			FROM TruckerProfiles
			WHERE PlayerID = ?
			LIMIT 1
		]], { pid })
		local r = RowsFirst(rows)
		if not r then return nil end
		return {
			playerId = tostring(DB.RowGet(r, "PlayerID") or pid),
			name = DB.RowGet(r, "Name"),
			phone = DB.RowGet(r, "Phone"),
			level = tonumber(DB.RowGet(r, "Level") or 1) or 1,
			skillsJson = DB.RowGet(r, "SkillsJson"),
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
		}
	end

	function DB.Trucker.EnsureProfile(playerId, defaults)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then return nil end
		local existing = DB.Trucker.GetProfile(pid)
		if existing then return existing end
		defaults = type(defaults) == "table" and defaults or {}
		local now = Now()
		Database.Execute([[
			INSERT INTO TruckerProfiles (
				PlayerID, Name, Phone, Level, SkillsJson, UpdatedAt
			) VALUES (?, ?, ?, ?, ?, ?)
		]], {
			pid,
			tostring(defaults.name or "Driver"),
			tostring(defaults.phone or "N/A"),
			tonumber(defaults.level or 1) or 1,
			defaults.skillsJson ~= nil and tostring(defaults.skillsJson) or "[]",
			now
		})
		return DB.Trucker.GetProfile(pid)
	end

	function DB.Trucker.GetOrderById(orderId)
		EnsureReady()
		local id = tostring(orderId or "")
		if id == "" then return nil end
		local rows = Database.Select([[
			SELECT ID, AssignedPlayerID, Title, ClientName, CargoName, CargoClass, WeightKg, PickupLabel, DropoffLabel, DistanceKm, Reward, Deposit, VehicleClass, TrailerRequired, Status, EstimatedMinutes, DeadlineAt, Description, MinLevel, RequiredSkillsJson, IconImage, TruckImage, TrailerImage, CargoImage, CreatedAt, UpdatedAt
			FROM TruckerOrders
			WHERE ID = ?
			LIMIT 1
		]], { id })
		local r = RowsFirst(rows)
		if not r then return nil end
		return {
			id = tostring(DB.RowGet(r, "ID") or ""),
			assignedPlayerId = DB.RowGet(r, "AssignedPlayerID"),
			title = tostring(DB.RowGet(r, "Title") or ""),
			clientName = tostring(DB.RowGet(r, "ClientName") or ""),
			cargoName = tostring(DB.RowGet(r, "CargoName") or ""),
			cargoClass = tostring(DB.RowGet(r, "CargoClass") or "standard"),
			weightKg = tonumber(DB.RowGet(r, "WeightKg") or 0) or 0,
			pickupLabel = tostring(DB.RowGet(r, "PickupLabel") or ""),
			dropoffLabel = tostring(DB.RowGet(r, "DropoffLabel") or ""),
			distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			deposit = tonumber(DB.RowGet(r, "Deposit") or 0) or 0,
			vehicleClass = DB.RowGet(r, "VehicleClass"),
			trailerRequired = (tonumber(DB.RowGet(r, "TrailerRequired") or 0) == 1),
			status = tostring(DB.RowGet(r, "Status") or "available"),
			estimatedMinutes = tonumber(DB.RowGet(r, "EstimatedMinutes") or 0) or 0,
			deadlineAt = tonumber(DB.RowGet(r, "DeadlineAt") or 0) or 0,
			description = DB.RowGet(r, "Description"),
			minLevel = tonumber(DB.RowGet(r, "MinLevel") or 1) or 1,
			requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
			iconImage = DB.RowGet(r, "IconImage"),
			truckImage = DB.RowGet(r, "TruckImage"),
			trailerImage = DB.RowGet(r, "TrailerImage"),
			cargoImage = DB.RowGet(r, "CargoImage"),
			createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
		}
	end

	function DB.Trucker.ListAvailableOrders(limit)
		EnsureReady()
		local lim = tonumber(limit) or 50
		local rows = Database.Select([[
			SELECT ID, AssignedPlayerID, Title, ClientName, CargoName, CargoClass, WeightKg, PickupLabel, DropoffLabel, DistanceKm, Reward, Deposit, VehicleClass, TrailerRequired, Status, EstimatedMinutes, DeadlineAt, Description, MinLevel, RequiredSkillsJson, IconImage, TruckImage, TrailerImage, CargoImage, CreatedAt, UpdatedAt
			FROM TruckerOrders
			WHERE Status = 'available'
			AND (AssignedPlayerID IS NULL OR AssignedPlayerID = '')
			ORDER BY CreatedAt DESC
			LIMIT ?
		]], { lim })
		local out = {}
		for i = 1, RowsCount(rows) do
			local r = RowAt(rows, i)
			out[#out + 1] = {
				id = tostring(DB.RowGet(r, "ID") or ""),
				assignedPlayerId = DB.RowGet(r, "AssignedPlayerID"),
				title = tostring(DB.RowGet(r, "Title") or ""),
				clientName = tostring(DB.RowGet(r, "ClientName") or ""),
				cargoName = tostring(DB.RowGet(r, "CargoName") or ""),
				cargoClass = tostring(DB.RowGet(r, "CargoClass") or "standard"),
				weightKg = tonumber(DB.RowGet(r, "WeightKg") or 0) or 0,
				pickupLabel = tostring(DB.RowGet(r, "PickupLabel") or ""),
				dropoffLabel = tostring(DB.RowGet(r, "DropoffLabel") or ""),
				distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
				reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
				deposit = tonumber(DB.RowGet(r, "Deposit") or 0) or 0,
				vehicleClass = DB.RowGet(r, "VehicleClass"),
				trailerRequired = (tonumber(DB.RowGet(r, "TrailerRequired") or 0) == 1),
				status = tostring(DB.RowGet(r, "Status") or "available"),
				estimatedMinutes = tonumber(DB.RowGet(r, "EstimatedMinutes") or 0) or 0,
				deadlineAt = tonumber(DB.RowGet(r, "DeadlineAt") or 0) or 0,
				description = DB.RowGet(r, "Description"),
				minLevel = tonumber(DB.RowGet(r, "MinLevel") or 1) or 1,
				requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
				iconImage = DB.RowGet(r, "IconImage"),
				truckImage = DB.RowGet(r, "TruckImage"),
				trailerImage = DB.RowGet(r, "TrailerImage"),
				cargoImage = DB.RowGet(r, "CargoImage"),
				createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
				updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
			}
		end
		return out
	end

	function DB.Trucker.GetActiveOrder(playerId)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then return nil end
		local rows = Database.Select([[
			SELECT ID, AssignedPlayerID, Title, ClientName, CargoName, CargoClass, WeightKg, PickupLabel, DropoffLabel, DistanceKm, Reward, Deposit, VehicleClass, TrailerRequired, Status, EstimatedMinutes, DeadlineAt, Description, MinLevel, RequiredSkillsJson, IconImage, TruckImage, TrailerImage, CargoImage, CreatedAt, UpdatedAt
			FROM TruckerOrders
			WHERE AssignedPlayerID = ?
			AND Status IN ('accepted', 'pickup', 'in_transit')
			ORDER BY UpdatedAt DESC
			LIMIT 1
		]], { pid })
		local r = RowsFirst(rows)
		if not r then return nil end
		return {
			id = tostring(DB.RowGet(r, "ID") or ""),
			assignedPlayerId = DB.RowGet(r, "AssignedPlayerID"),
			title = tostring(DB.RowGet(r, "Title") or ""),
			clientName = tostring(DB.RowGet(r, "ClientName") or ""),
			cargoName = tostring(DB.RowGet(r, "CargoName") or ""),
			cargoClass = tostring(DB.RowGet(r, "CargoClass") or "standard"),
			weightKg = tonumber(DB.RowGet(r, "WeightKg") or 0) or 0,
			pickupLabel = tostring(DB.RowGet(r, "PickupLabel") or ""),
			dropoffLabel = tostring(DB.RowGet(r, "DropoffLabel") or ""),
			distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			deposit = tonumber(DB.RowGet(r, "Deposit") or 0) or 0,
			vehicleClass = DB.RowGet(r, "VehicleClass"),
			trailerRequired = (tonumber(DB.RowGet(r, "TrailerRequired") or 0) == 1),
			status = tostring(DB.RowGet(r, "Status") or "accepted"),
			estimatedMinutes = tonumber(DB.RowGet(r, "EstimatedMinutes") or 0) or 0,
			deadlineAt = tonumber(DB.RowGet(r, "DeadlineAt") or 0) or 0,
			description = DB.RowGet(r, "Description"),
			minLevel = tonumber(DB.RowGet(r, "MinLevel") or 1) or 1,
			requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
			iconImage = DB.RowGet(r, "IconImage"),
			truckImage = DB.RowGet(r, "TruckImage"),
			trailerImage = DB.RowGet(r, "TrailerImage"),
			cargoImage = DB.RowGet(r, "CargoImage"),
			createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
		}
	end

	function DB.Trucker.TryAssignOrder(orderId, playerId)
		EnsureReady()
		local oid = tostring(orderId or "")
		local pid = tostring(playerId or "")
		if oid == "" or pid == "" then return false end
		local now = Now()
		return Database.Execute([[
			UPDATE TruckerOrders
			SET AssignedPlayerID = ?, Status = 'accepted', UpdatedAt = ?
			WHERE ID = ?
			AND Status = 'available'
			AND (AssignedPlayerID IS NULL OR AssignedPlayerID = '')
		]], { pid, now, oid }) == true
	end

	function DB.Courier.GetProfile(playerId)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then return nil end
		local rows = Database.Select([[
			SELECT PlayerID, Level, Rating, CompletedJobs, TotalEarned, SkillPoints, UpdatedAt
			FROM CourierProfiles
			WHERE PlayerID = ?
			LIMIT 1
		]], { pid })
		local r = RowsFirst(rows)
		if not r then return nil end
		return {
			playerId = tostring(DB.RowGet(r, "PlayerID") or pid),
			level = tonumber(DB.RowGet(r, "Level") or 1) or 1,
			rating = tonumber(DB.RowGet(r, "Rating") or 5.0) or 5.0,
			completedJobs = tonumber(DB.RowGet(r, "CompletedJobs") or 0) or 0,
			totalEarned = tonumber(DB.RowGet(r, "TotalEarned") or 0) or 0,
			skillPoints = tonumber(DB.RowGet(r, "SkillPoints") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
		}
	end

	function DB.Courier.EnsureProfile(playerId)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then return nil end
		local existing = DB.Courier.GetProfile(pid)
		if existing then return existing end
		local now = Now()
		Database.Execute([[
			INSERT INTO CourierProfiles (
				PlayerID, Level, Rating, CompletedJobs, TotalEarned, SkillPoints, UpdatedAt
			) VALUES (?, ?, ?, ?, ?, ?, ?)
		]], { pid, 1, 5.0, 0, 0, 0, now })
		return DB.Courier.GetProfile(pid)
	end

	function DB.Courier.GetJobById(jobId)
		EnsureReady()
		local id = tostring(jobId or "")
		if id == "" then return nil end
		local rows = Database.Select([[
			SELECT ID, PlayerID, Title, Customer, Pickup, Dropoff, Reward, DistanceKm, Status, Priority, RequiredSkillsJson, Notes, InvoiceNumber, CreatedAt, UpdatedAt, CompletedAt
			FROM CourierJobs
			WHERE ID = ?
			LIMIT 1
		]], { id })
		local r = RowsFirst(rows)
		if not r then return nil end
		return {
			id = tostring(DB.RowGet(r, "ID") or ""),
			playerId = DB.RowGet(r, "PlayerID"),
			title = tostring(DB.RowGet(r, "Title") or ""),
			customer = tostring(DB.RowGet(r, "Customer") or ""),
			pickup = tostring(DB.RowGet(r, "Pickup") or ""),
			dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
			status = tostring(DB.RowGet(r, "Status") or "available"),
			priority = tostring(DB.RowGet(r, "Priority") or "normal"),
			requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
			notes = tostring(DB.RowGet(r, "Notes") or ""),
			invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
			createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
			completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
		}
	end

	function DB.Courier.ListAvailableJobs(limit)
		EnsureReady()
		local lim = tonumber(limit) or 50
		local rows = Database.Select([[
			SELECT ID, PlayerID, Title, Customer, Pickup, Dropoff, Reward, DistanceKm, Status, Priority, RequiredSkillsJson, Notes, InvoiceNumber, CreatedAt, UpdatedAt, CompletedAt
			FROM CourierJobs
			WHERE Status IN ('available', 'active')
			ORDER BY CreatedAt DESC
			LIMIT ?
		]], { lim })
		local out = {}
		for i = 1, RowsCount(rows) do
			local r = RowAt(rows, i)
			out[#out + 1] = {
				id = tostring(DB.RowGet(r, "ID") or ""),
				playerId = DB.RowGet(r, "PlayerID"),
				title = tostring(DB.RowGet(r, "Title") or ""),
				customer = tostring(DB.RowGet(r, "Customer") or ""),
				pickup = tostring(DB.RowGet(r, "Pickup") or ""),
				dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
				reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
				distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
				status = tostring(DB.RowGet(r, "Status") or "available"),
				priority = tostring(DB.RowGet(r, "Priority") or "normal"),
				requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
				notes = tostring(DB.RowGet(r, "Notes") or ""),
				invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
				createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
				updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
				completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
			}
		end
		return out
	end

	function DB.Courier.GetActiveJob(playerId)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then return nil end
		local rows = Database.Select([[
			SELECT ID, PlayerID, Title, Customer, Pickup, Dropoff, Reward, DistanceKm, Status, Priority, RequiredSkillsJson, Notes, InvoiceNumber, CreatedAt, UpdatedAt, CompletedAt
			FROM CourierJobs
			WHERE PlayerID = ? AND Status = 'active'
			ORDER BY UpdatedAt DESC
			LIMIT 1
		]], { pid })
		local r = RowsFirst(rows)
		if not r then return nil end
		return {
			id = tostring(DB.RowGet(r, "ID") or ""),
			playerId = DB.RowGet(r, "PlayerID"),
			title = tostring(DB.RowGet(r, "Title") or ""),
			customer = tostring(DB.RowGet(r, "Customer") or ""),
			pickup = tostring(DB.RowGet(r, "Pickup") or ""),
			dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
			status = tostring(DB.RowGet(r, "Status") or "active"),
			priority = tostring(DB.RowGet(r, "Priority") or "normal"),
			requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
			notes = tostring(DB.RowGet(r, "Notes") or ""),
			invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
			createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
			completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
		}
	end

	function DB.Courier.ListHistory(playerId, limit)
		EnsureReady()
		local pid = tostring(playerId or "")
		local lim = tonumber(limit) or 50
		if pid == "" then return {} end
		local rows = Database.Select([[
			SELECT ID, PlayerID, Title, Customer, Pickup, Dropoff, Reward, DistanceKm, Status, Priority, RequiredSkillsJson, Notes, InvoiceNumber, CreatedAt, UpdatedAt, CompletedAt
			FROM CourierJobs
			WHERE PlayerID = ? AND Status IN ('completed', 'cancelled')
			ORDER BY UpdatedAt DESC
			LIMIT ?
		]], { pid, lim })
		local out = {}
		for i = 1, RowsCount(rows) do
			local r = RowAt(rows, i)
			out[#out + 1] = {
				id = tostring(DB.RowGet(r, "ID") or ""),
				title = tostring(DB.RowGet(r, "Title") or ""),
				customer = tostring(DB.RowGet(r, "Customer") or ""),
				reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
				status = tostring(DB.RowGet(r, "Status") or ""),
				invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
				updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
				completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
			}
		end
		return out
	end

	function DB.Courier.UpsertInvoice(data)
		EnsureReady()
		data = type(data) == "table" and data or {}
		local invoiceId = tostring(data.invoiceId or "")
		local playerId = tostring(data.playerId or "")
		local jobId = tostring(data.jobId or "")
		local status = tostring(data.status or "printed")
		local metaJson = data.metaJson ~= nil and tostring(data.metaJson) or nil
		if invoiceId == "" or playerId == "" or jobId == "" then return false end
		local now = Now()
		local existing = Database.Select([[SELECT InvoiceID FROM CourierInvoices WHERE InvoiceID = ? LIMIT 1]], { invoiceId })
		if RowsCount(existing) <= 0 then
			return Database.Execute([[
				INSERT INTO CourierInvoices (
					InvoiceID, PlayerID, JobID, Status, MetaJson, CreatedAt, UpdatedAt
				) VALUES (?, ?, ?, ?, ?, ?, ?)
			]], { invoiceId, playerId, jobId, status, metaJson, now, now }) == true
		end
		return Database.Execute([[
			UPDATE CourierInvoices SET
				PlayerID = ?,
				JobID = ?,
				Status = ?,
				MetaJson = ?,
				UpdatedAt = ?
			WHERE InvoiceID = ?
		]], { playerId, jobId, status, metaJson, now, invoiceId }) == true
	end

	function DB.Courier.ListOpenJobs(limit)
		EnsureReady()
		local lim = tonumber(limit) or 50
		local rows = Database.Select([[
			SELECT ID, PlayerID, Title, Customer, Pickup, Dropoff, Reward, DistanceKm, Status, Priority, RequiredSkillsJson, Notes, InvoiceNumber, CreatedAt, UpdatedAt, CompletedAt
			FROM CourierJobs
			WHERE (PlayerID IS NULL OR PlayerID = '')
			AND Status = 'available'
			ORDER BY CreatedAt DESC
			LIMIT ?
		]], { lim })
		local out = {}
		for i = 1, RowsCount(rows) do
			local r = RowAt(rows, i)
			out[#out + 1] = {
				id = tostring(DB.RowGet(r, "ID") or ""),
				playerId = DB.RowGet(r, "PlayerID"),
				title = tostring(DB.RowGet(r, "Title") or ""),
				customer = tostring(DB.RowGet(r, "Customer") or ""),
				pickup = tostring(DB.RowGet(r, "Pickup") or ""),
				dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
				reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
				distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
				status = tostring(DB.RowGet(r, "Status") or "available"),
				priority = tostring(DB.RowGet(r, "Priority") or "normal"),
				requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
				notes = tostring(DB.RowGet(r, "Notes") or ""),
				invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
				createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
				updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
				completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
			}
		end
		return out
	end

	function DB.Courier.GetAnyOwnedActiveJob(playerId)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then return nil end
		local rows = Database.Select([[
			SELECT ID, PlayerID, Title, Customer, Pickup, Dropoff, Reward, DistanceKm, Status, Priority, RequiredSkillsJson, Notes, InvoiceNumber, CreatedAt, UpdatedAt, CompletedAt
			FROM CourierJobs
			WHERE PlayerID = ?
			AND Status IN ('active', 'pickup', 'delivery', 'accepted')
			ORDER BY UpdatedAt DESC
			LIMIT 1
		]], { pid })
		local r = RowsFirst(rows)
		if not r then return nil end
		return {
			id = tostring(DB.RowGet(r, "ID") or ""),
			playerId = DB.RowGet(r, "PlayerID"),
			title = tostring(DB.RowGet(r, "Title") or ""),
			customer = tostring(DB.RowGet(r, "Customer") or ""),
			pickup = tostring(DB.RowGet(r, "Pickup") or ""),
			dropoff = tostring(DB.RowGet(r, "Dropoff") or ""),
			reward = tonumber(DB.RowGet(r, "Reward") or 0) or 0,
			distanceKm = tonumber(DB.RowGet(r, "DistanceKm") or 0) or 0,
			status = tostring(DB.RowGet(r, "Status") or "active"),
			priority = tostring(DB.RowGet(r, "Priority") or "normal"),
			requiredSkillsJson = DB.RowGet(r, "RequiredSkillsJson"),
			notes = tostring(DB.RowGet(r, "Notes") or ""),
			invoiceNumber = DB.RowGet(r, "InvoiceNumber"),
			createdAt = tonumber(DB.RowGet(r, "CreatedAt") or 0) or 0,
			updatedAt = tonumber(DB.RowGet(r, "UpdatedAt") or 0) or 0,
			completedAt = tonumber(DB.RowGet(r, "CompletedAt") or 0) or 0,
		}
	end

	function DB.Courier.TryAssignJob(jobId, playerId)
		EnsureReady()
		local jid = tostring(jobId or "")
		local pid = tostring(playerId or "")
		if jid == "" or pid == "" then return false end
		local now = Now()
		return Database.Execute([[
			UPDATE CourierJobs
			SET PlayerID = ?, Status = 'active', UpdatedAt = ?
			WHERE ID = ?
			AND (PlayerID IS NULL OR PlayerID = '')
			AND Status = 'available'
		]], { pid, now, jid }) == true
	end

	function DB.Courier.MarkJobCompleted(jobId, playerId)
		EnsureReady()
		local jid = tostring(jobId or "")
		local pid = tostring(playerId or "")
		if jid == "" or pid == "" then return false end
		local now = Now()
		return Database.Execute([[
			UPDATE CourierJobs
			SET Status = 'completed', UpdatedAt = ?, CompletedAt = ?
			WHERE ID = ?
			AND PlayerID = ?
			AND Status IN ('active', 'pickup', 'delivery', 'accepted')
		]], { now, now, jid, pid }) == true
	end

	function DB.Courier.CancelJob(jobId, playerId)
		EnsureReady()
		local jid = tostring(jobId or "")
		local pid = tostring(playerId or "")
		if jid == "" or pid == "" then return false end
		local now = Now()
		return Database.Execute([[
			UPDATE CourierJobs
			SET Status = 'cancelled', UpdatedAt = ?
			WHERE ID = ?
			AND PlayerID = ?
			AND Status IN ('active', 'pickup', 'delivery', 'accepted')
		]], { now, jid, pid }) == true
	end

	function DB.Courier.GetSkills(playerId)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then
			return { standard = 0, fragile = 0, medical = 0, secure = 0 }
		end
		return { standard = 0, fragile = 0, medical = 0, secure = 0 }
	end

	function DB.Courier.UpdateProfileProgress(playerId, reward)
		EnsureReady()
		local pid = tostring(playerId or "")
		if pid == "" then return false end
		local amount = tonumber(reward or 0) or 0
		local profile = DB.Courier.EnsureProfile(pid)
		if not profile then return false end
		local now = Now()
		local nextCompletedJobs = (tonumber(profile.completedJobs or 0) or 0) + 1
		local nextTotalEarned = (tonumber(profile.totalEarned or 0) or 0) + amount
		local currentLevel = tonumber(profile.level or 1) or 1
		local nextLevel = currentLevel
		if nextCompletedJobs >= (currentLevel * 5) then
			nextLevel = currentLevel + 1
		end
		return Database.Execute([[
			UPDATE CourierProfiles
			SET Level = ?, CompletedJobs = ?, TotalEarned = ?, UpdatedAt = ?
			WHERE PlayerID = ?
		]], { nextLevel, nextCompletedJobs, nextTotalEarned, now, pid }) == true
	end

	return DB
end

return Apply
