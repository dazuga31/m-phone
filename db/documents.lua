local function Apply(DB)
	local function EnsureReady()
		if DB and DB.Init then DB.Init() end
	end

	local RowAt = DB.RowAt

	local function Encode(value)
		if type(value) ~= "table" then return "{}" end

		if JSON and type(JSON.stringify) == "function" then
			local ok, encoded = pcall(function()
				return JSON.stringify(value)
			end)
			if ok and type(encoded) == "string" and encoded ~= "" then return encoded end
		end

		if json and type(json.encode) == "function" then
			local ok, encoded = pcall(function()
				return json.encode(value)
			end)
			if ok and type(encoded) == "string" and encoded ~= "" then return encoded end
		end

		return nil
	end

	local function Decode(value)
		local raw = tostring(value or "")
		if raw == "" then return {} end

		if JSON and type(JSON.parse) == "function" then
			local ok, decoded = pcall(function()
				return JSON.parse(raw)
			end)
			if ok and type(decoded) == "table" then return decoded end
		end

		if json and type(json.decode) == "function" then
			local ok, decoded = pcall(function()
				return json.decode(raw)
			end)
			if ok and type(decoded) == "table" then return decoded end
		end

		return {}
	end

	local function MapRow(row)
		if not row then return nil end
		local payload = Decode(DB.RowGet(row, "PayloadJson", "payloadJson"))

		payload.id = tostring(DB.RowGet(row, "ID", "id") or payload.id or "")
		payload.type = tostring(DB.RowGet(row, "DocumentType", "documentType") or payload.type or "")
		payload.number = tostring(DB.RowGet(row, "DocumentNumber", "documentNumber") or payload.number or "")
		payload.holderId = tostring(DB.RowGet(row, "HolderID", "holderId") or payload.holderId or "")
		payload.status = tostring(DB.RowGet(row, "Status", "status") or payload.status or "active")
		payload.issuedAtUnix = tonumber(DB.RowGet(row, "IssuedAt", "issuedAt") or 0) or 0
		payload.expiresAtUnix = tonumber(DB.RowGet(row, "ExpiresAt", "expiresAt") or 0) or 0
		payload.issuedBy = tostring(DB.RowGet(row, "IssuedBy", "issuedBy") or payload.issuedBy or "")
		payload.photoUid = tostring(DB.RowGet(row, "PhotoUID", "photoUid") or payload.photoUid or "")
		payload.photoUrl = tostring(DB.RowGet(row, "PhotoURL", "photoUrl") or payload.photoUrl or "")
		payload.issueRequestId = tostring(DB.RowGet(row, "IssueRequestID", "issueRequestId") or "")
		payload.replacedById = tostring(DB.RowGet(row, "ReplacedByID", "replacedById") or "")
		payload.revokedAt = tonumber(DB.RowGet(row, "RevokedAt", "revokedAt") or 0) or 0
		payload.createdAt = tonumber(DB.RowGet(row, "CreatedAt", "createdAt") or 0) or 0
		payload.updatedAt = tonumber(DB.RowGet(row, "UpdatedAt", "updatedAt") or 0) or 0
		payload.fields = type(payload.fields) == "table" and payload.fields or {}

		return payload
	end

	DB.Documents = DB.Documents or {}

	function DB.Documents.Get(documentId)
		EnsureReady()
		local rows = Database.Select("SELECT * FROM PlayerDocuments WHERE ID = ? LIMIT 1", {
			tostring(documentId or ""),
		})
		return MapRow(RowAt(rows, 1))
	end

	function DB.Documents.GetByRequestId(requestId)
		EnsureReady()
		local rows = Database.Select("SELECT * FROM PlayerDocuments WHERE IssueRequestID = ? LIMIT 1", {
			tostring(requestId or ""),
		})
		return MapRow(RowAt(rows, 1))
	end

	function DB.Documents.GetActive(holderId, documentType)
		EnsureReady()
		local rows = Database.Select([[
			SELECT * FROM PlayerDocuments
			WHERE HolderID = ? AND DocumentType = ? AND Status = 'active'
			ORDER BY IssuedAt DESC
			LIMIT 1
		]], {
			tostring(holderId or ""),
			tostring(documentType or ""),
		})
		return MapRow(RowAt(rows, 1))
	end

	function DB.Documents.CreatePending(document)
		EnsureReady()
		document = type(document) == "table" and document or {}

		local id = tostring(document.id or "")
		local documentType = tostring(document.type or "")
		local number = tostring(document.number or "")
		local holderId = tostring(document.holderId or "")
		local requestId = tostring(document.issueRequestId or "")
		if id == "" or documentType == "" or number == "" or holderId == "" or requestId == "" then
			return false, "invalid_document"
		end

		local now = os.time()
		local payloadJson = Encode(document)
		if not payloadJson then
			print("[m-phone][documents][db][error] No compatible JSON encoder is available")
			return false, "document_create_failed"
		end
		local ok = Database.Execute([[
			INSERT INTO PlayerDocuments (
				ID, DocumentType, DocumentNumber, HolderID, Status,
				IssuedAt, ExpiresAt, IssuedBy, PhotoUID, PhotoURL,
				PayloadJson, IssueRequestID, ReplacedByID, RevokedAt,
				CreatedAt, UpdatedAt
			) VALUES (?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?, '', 0, ?, ?)
		]], {
			id,
			documentType,
			number,
			holderId,
			math.floor(tonumber(document.issuedAtUnix) or now),
			math.floor(tonumber(document.expiresAtUnix) or 0),
			tostring(document.issuedBy or ""),
			tostring(document.photoUid or ""),
			tostring(document.photoUrl or ""),
			payloadJson,
			requestId,
			now,
			now,
		}) == true

		return ok, ok and nil or "document_create_failed"
	end

	function DB.Documents.SetStatus(documentId, status)
		EnsureReady()
		return Database.Execute("UPDATE PlayerDocuments SET Status = ?, UpdatedAt = ? WHERE ID = ?", {
			tostring(status or ""),
			os.time(),
			tostring(documentId or ""),
		}) == true
	end

	function DB.Documents.Cancel(documentId)
		return DB.Documents.SetStatus(documentId, "cancelled")
	end
end

return Apply
