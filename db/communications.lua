local function Apply(DB)
	local function EnsureReady()
		if DB and DB.Init then DB.Init() end
	end

	local RowsCount = DB.RowsCount
	local RowAt = DB.RowAt

	local function First(rows)
		return RowsCount(rows) > 0 and RowAt(rows, 1) or nil
	end

	local function Value(row, ...)
		return row and DB.RowGet(row, ...) or nil
	end

	DB.Communications = DB.Communications or {}

	function DB.Communications.GetProfileByPlayerId(playerId)
		EnsureReady()
		return First(Database.Select([[SELECT PlayerID, CitizenID, PhoneNumber, DisplayName, CreatedAt, UpdatedAt FROM PhoneProfiles WHERE PlayerID = ? LIMIT 1]], { tostring(playerId or "") }))
	end

	function DB.Communications.GetProfileByCitizenId(citizenId)
		EnsureReady()
		return First(Database.Select([[SELECT PlayerID, CitizenID, PhoneNumber, DisplayName, CreatedAt, UpdatedAt FROM PhoneProfiles WHERE CitizenID = ? LIMIT 1]], { tostring(citizenId or "") }))
	end

	function DB.Communications.GetProfileByPhone(phoneNumber)
		EnsureReady()
		return First(Database.Select([[SELECT PlayerID, CitizenID, PhoneNumber, DisplayName, CreatedAt, UpdatedAt FROM PhoneProfiles WHERE PhoneNumber = ? LIMIT 1]], { tostring(phoneNumber or "") }))
	end

	function DB.Communications.UpsertProfile(playerId, citizenId, phoneNumber, displayName)
		EnsureReady()
		local now = math.floor(os.time() * 1000)
		return Database.Execute([[
			INSERT INTO PhoneProfiles (PlayerID, CitizenID, PhoneNumber, DisplayName, CreatedAt, UpdatedAt)
			VALUES (?, ?, ?, ?, ?, ?)
			ON CONFLICT(PlayerID) DO UPDATE SET
				CitizenID = excluded.CitizenID,
				PhoneNumber = excluded.PhoneNumber,
				DisplayName = excluded.DisplayName,
				UpdatedAt = excluded.UpdatedAt
		]], { tostring(playerId), tostring(citizenId), tostring(phoneNumber), tostring(displayName), now, now }) == true
	end

	function DB.Communications.ListContacts(ownerPlayerId)
		EnsureReady()
		local rows = Database.Select([[
			SELECT c.ContactID, c.ContactName, c.PhoneNumber, c.CreatedAt, c.UpdatedAt,
				COALESCE(f.IsFavorite, 0) AS IsFavorite, COALESCE(f.IsBlocked, 0) AS IsBlocked
			FROM PhoneContacts c
			LEFT JOIN PhoneContactFlags f ON f.OwnerPlayerID = c.OwnerPlayerID AND f.PhoneNumber = c.PhoneNumber
			WHERE c.OwnerPlayerID = ?
			ORDER BY COALESCE(f.IsFavorite, 0) DESC, c.ContactName COLLATE NOCASE ASC
		]], { tostring(ownerPlayerId or "") })
		local out = {}
		for index = 1, RowsCount(rows) do
			local row = RowAt(rows, index)
			out[#out + 1] = {
				id = tostring(Value(row, "ContactID", "contactid") or ""),
				name = tostring(Value(row, "ContactName", "contactname") or "Unknown"),
				phoneNumber = tostring(Value(row, "PhoneNumber", "phonenumber") or ""),
				createdAt = tonumber(Value(row, "CreatedAt", "createdat") or 0) or 0,
				updatedAt = tonumber(Value(row, "UpdatedAt", "updatedat") or 0) or 0,
				isFavorite = tonumber(Value(row, "IsFavorite", "isfavorite") or 0) == 1,
				isBlocked = tonumber(Value(row, "IsBlocked", "isblocked") or 0) == 1,
			}
		end
		return out
	end

	function DB.Communications.CountContacts(ownerPlayerId)
		EnsureReady()
		local row = First(Database.Select([[SELECT COUNT(*) AS Total FROM PhoneContacts WHERE OwnerPlayerID = ?]], { tostring(ownerPlayerId or "") }))
		return tonumber(Value(row, "Total", "total") or 0) or 0
	end

	function DB.Communications.UpsertContact(ownerPlayerId, contactId, contactName, phoneNumber)
		EnsureReady()
		local now = math.floor(os.time() * 1000)
		return Database.Execute([[
			INSERT INTO PhoneContacts (OwnerPlayerID, ContactID, ContactName, PhoneNumber, CreatedAt, UpdatedAt)
			VALUES (?, ?, ?, ?, ?, ?)
			ON CONFLICT(OwnerPlayerID, PhoneNumber) DO UPDATE SET
				ContactName = excluded.ContactName,
				UpdatedAt = excluded.UpdatedAt
		]], { tostring(ownerPlayerId), tostring(contactId), tostring(contactName), tostring(phoneNumber), now, now }) == true
	end

	function DB.Communications.DeleteContact(ownerPlayerId, contactId)
		EnsureReady()
		return Database.Execute([[DELETE FROM PhoneContacts WHERE OwnerPlayerID = ? AND ContactID = ?]], { tostring(ownerPlayerId or ""), tostring(contactId or "") }) == true
	end

	function DB.Communications.SetContactFlags(ownerPlayerId, phoneNumber, isFavorite, isBlocked)
		EnsureReady()
		local now = math.floor(os.time() * 1000)
		return Database.Execute([[
			INSERT INTO PhoneContactFlags (OwnerPlayerID, PhoneNumber, IsFavorite, IsBlocked, UpdatedAt)
			VALUES (?, ?, ?, ?, ?)
			ON CONFLICT(OwnerPlayerID, PhoneNumber) DO UPDATE SET
				IsFavorite = excluded.IsFavorite,
				IsBlocked = excluded.IsBlocked,
				UpdatedAt = excluded.UpdatedAt
		]], { tostring(ownerPlayerId), tostring(phoneNumber), isFavorite and 1 or 0, isBlocked and 1 or 0, now }) == true
	end

	function DB.Communications.GetContactFlags(ownerPlayerId, phoneNumber)
		EnsureReady()
		local row = First(Database.Select([[SELECT IsFavorite, IsBlocked FROM PhoneContactFlags WHERE OwnerPlayerID = ? AND PhoneNumber = ? LIMIT 1]], { tostring(ownerPlayerId or ""), tostring(phoneNumber or "") }))
		return {
			isFavorite = row and tonumber(Value(row, "IsFavorite", "isfavorite") or 0) == 1 or false,
			isBlocked = row and tonumber(Value(row, "IsBlocked", "isblocked") or 0) == 1 or false,
		}
	end

	function DB.Communications.IsBlocked(ownerPlayerId, phoneNumber)
		return DB.Communications.GetContactFlags(ownerPlayerId, phoneNumber).isBlocked == true
	end

	function DB.Communications.CreateSmsReceipt(messageId, senderPlayerId, recipientPlayerId, senderConvId, recipientConvId, status, createdAt)
		EnsureReady()
		local deliveredAt = status == "delivered" and tonumber(createdAt) or 0
		return Database.Execute([[
			INSERT INTO PhoneSmsReceipts (MessageID, SenderPlayerID, RecipientPlayerID, SenderConversationID, RecipientConversationID, Status, CreatedAt, DeliveredAt, ReadAt)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
		]], { tostring(messageId), tostring(senderPlayerId), tostring(recipientPlayerId), tostring(senderConvId), tostring(recipientConvId), tostring(status or "sent"), tonumber(createdAt) or 0, deliveredAt or 0 }) == true
	end

	function DB.Communications.ListSmsStatuses(senderPlayerId, senderConvId)
		EnsureReady()
		local rows = Database.Select([[SELECT MessageID, Status, DeliveredAt, ReadAt FROM PhoneSmsReceipts WHERE SenderPlayerID = ? AND SenderConversationID = ?]], { tostring(senderPlayerId or ""), tostring(senderConvId or "") })
		local out = {}
		for index = 1, RowsCount(rows) do
			local row = RowAt(rows, index)
			out[tostring(Value(row, "MessageID", "messageid") or "")] = {
				status = tostring(Value(row, "Status", "status") or "sent"),
				deliveredAt = tonumber(Value(row, "DeliveredAt", "deliveredat") or 0) or 0,
				readAt = tonumber(Value(row, "ReadAt", "readat") or 0) or 0,
			}
		end
		return out
	end

	function DB.Communications.MarkSmsRead(recipientPlayerId, recipientConvId, readAt)
		EnsureReady()
		local rows = Database.Select([[SELECT MessageID, SenderPlayerID, SenderConversationID FROM PhoneSmsReceipts WHERE RecipientPlayerID = ? AND RecipientConversationID = ? AND Status <> 'read']], { tostring(recipientPlayerId or ""), tostring(recipientConvId or "") })
		local updated = {}
		for index = 1, RowsCount(rows) do
			local row = RowAt(rows, index)
			updated[#updated + 1] = {
				messageId = tostring(Value(row, "MessageID", "messageid") or ""),
				senderPlayerId = tostring(Value(row, "SenderPlayerID", "senderplayerid") or ""),
				senderConvId = tostring(Value(row, "SenderConversationID", "senderconversationid") or ""),
			}
		end
		Database.Execute([[UPDATE PhoneSmsReceipts SET Status = 'read', ReadAt = ?, DeliveredAt = CASE WHEN DeliveredAt = 0 THEN ? ELSE DeliveredAt END WHERE RecipientPlayerID = ? AND RecipientConversationID = ? AND Status <> 'read']], { tonumber(readAt) or 0, tonumber(readAt) or 0, tostring(recipientPlayerId or ""), tostring(recipientConvId or "") })
		return updated
	end

	function DB.Communications.AddCallHistory(call)
		EnsureReady()
		return Database.Execute([[
			INSERT OR REPLACE INTO PhoneCallHistory (CallID, OwnerPlayerID, PeerPhoneNumber, PeerDisplayName, Direction, Status, StartedAt, AnsweredAt, EndedAt, DurationSeconds)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		]], { tostring(call.callId), tostring(call.ownerPlayerId), tostring(call.peerPhoneNumber), tostring(call.peerDisplayName or ""), tostring(call.direction), tostring(call.status), tonumber(call.startedAt) or 0, tonumber(call.answeredAt) or 0, tonumber(call.endedAt) or 0, tonumber(call.durationSeconds) or 0 }) == true
	end

	function DB.Communications.ListCallHistory(ownerPlayerId, limit, offset)
		EnsureReady()
		local rows = Database.Select([[SELECT CallID, PeerPhoneNumber, PeerDisplayName, Direction, Status, StartedAt, AnsweredAt, EndedAt, DurationSeconds FROM PhoneCallHistory WHERE OwnerPlayerID = ? ORDER BY StartedAt DESC LIMIT ? OFFSET ?]], { tostring(ownerPlayerId or ""), math.max(1, math.min(100, tonumber(limit) or 30)), math.max(0, tonumber(offset) or 0) })
		local out = {}
		for index = 1, RowsCount(rows) do
			local row = RowAt(rows, index)
			out[#out + 1] = {
				callId = tostring(Value(row, "CallID", "callid") or ""), peerPhoneNumber = tostring(Value(row, "PeerPhoneNumber", "peerphonenumber") or ""),
				peerDisplayName = tostring(Value(row, "PeerDisplayName", "peerdisplayname") or ""), direction = tostring(Value(row, "Direction", "direction") or "outgoing"),
				status = tostring(Value(row, "Status", "status") or "ended"), startedAt = tonumber(Value(row, "StartedAt", "startedat") or 0) or 0,
				answeredAt = tonumber(Value(row, "AnsweredAt", "answeredat") or 0) or 0, endedAt = tonumber(Value(row, "EndedAt", "endedat") or 0) or 0,
				durationSeconds = tonumber(Value(row, "DurationSeconds", "durationseconds") or 0) or 0,
			}
		end
		return out
	end

	function DB.Communications.ContactName(ownerPlayerId, phoneNumber)
		EnsureReady()
		local row = First(Database.Select([[SELECT ContactName FROM PhoneContacts WHERE OwnerPlayerID = ? AND PhoneNumber = ? LIMIT 1]], { tostring(ownerPlayerId or ""), tostring(phoneNumber or "") }))
		return row and tostring(Value(row, "ContactName", "contactname") or "") or ""
	end

	function DB.Communications.ProfileToTable(row)
		if not row then return nil end
		return {
			playerId = tostring(Value(row, "PlayerID", "playerid") or ""),
			citizenId = tostring(Value(row, "CitizenID", "citizenid") or ""),
			phoneNumber = tostring(Value(row, "PhoneNumber", "phonenumber") or ""),
			displayName = tostring(Value(row, "DisplayName", "displayname") or "Unknown"),
		}
	end

	return DB
end

return Apply
