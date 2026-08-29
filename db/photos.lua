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
			url = tostring(DB.RowGet(row, "ImageUrl") or ""),
			storageKey = tostring(DB.RowGet(row, "StorageKey") or ""),
			source = tostring(DB.RowGet(row, "Source") or "camera"),
			width = tonumber(DB.RowGet(row, "Width") or 0) or 0,
			height = tonumber(DB.RowGet(row, "Height") or 0) or 0,
			createdAt = tonumber(DB.RowGet(row, "CreatedAt") or 0) or 0,
		}
	end

	DB.Photos = DB.Photos or {}

	function DB.Photos.Count(playerId)
		EnsureReady()
		local rows = Database.Select("SELECT COUNT(*) AS Total FROM PhonePhotos WHERE PlayerID = ?", {
			tostring(playerId or ""),
		})
		local row = RowAt(rows, 1)
		return tonumber(DB.RowGet(row, "Total", "total", "COUNT(*)") or 0) or 0
	end

	function DB.Photos.List(playerId, limit, offset)
		EnsureReady()
		local rows = Database.Select([[
			SELECT ID, ImageUrl, StorageKey, Source, Width, Height, CreatedAt
			FROM PhonePhotos
			WHERE PlayerID = ?
			ORDER BY CreatedAt DESC
			LIMIT ? OFFSET ?
		]], {
			tostring(playerId or ""),
			math.max(1, math.min(200, math.floor(tonumber(limit) or 100))),
			math.max(0, math.floor(tonumber(offset) or 0)),
		})

		local result = {}
		for index = 1, RowsCount(rows) do
			local photo = MapRow(RowAt(rows, index))
			if photo then result[#result + 1] = photo end
		end
		return result
	end

	function DB.Photos.Get(playerId, photoId)
		EnsureReady()
		local rows = Database.Select([[
			SELECT ID, ImageUrl, StorageKey, Source, Width, Height, CreatedAt
			FROM PhonePhotos
			WHERE PlayerID = ? AND ID = ?
			LIMIT 1
		]], {
			tostring(playerId or ""),
			tostring(photoId or ""),
		})
		return MapRow(RowAt(rows, 1))
	end

	function DB.Photos.Create(photo)
		EnsureReady()
		photo = type(photo) == "table" and photo or {}
		local id = tostring(photo.id or "")
		local playerId = tostring(photo.playerId or "")
		local url = tostring(photo.url or "")
		if id == "" or playerId == "" or url == "" then return false end

		return Database.Execute([[
			INSERT INTO PhonePhotos (
				ID, PlayerID, ImageUrl, StorageKey, Source, Width, Height, CreatedAt
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		]], {
			id,
			playerId,
			url,
			tostring(photo.storageKey or ""),
			tostring(photo.source or "camera"),
			math.max(0, math.floor(tonumber(photo.width) or 0)),
			math.max(0, math.floor(tonumber(photo.height) or 0)),
			math.floor(tonumber(photo.createdAt) or os.time()),
		}) == true
	end

	function DB.Photos.Delete(playerId, photoId)
		EnsureReady()
		local pid = tostring(playerId or "")
		local id = tostring(photoId or "")
		if pid == "" or id == "" then return false end
		return Database.Execute("DELETE FROM PhonePhotos WHERE ID = ? AND PlayerID = ?", { id, pid }) == true
	end
end

return Apply
