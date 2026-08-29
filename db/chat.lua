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

	local function ClampInt(v, min, max, fallback)
		local n = tonumber(v)
		if n == nil then n = fallback or 0 end
		n = math.floor(n + 0.0)
		if min ~= nil and n < min then n = min end
		if max ~= nil and n > max then n = max end
		return n
	end

	local function SafeText(v, fallback)
		local s = tostring(v or "")
		if s == "" then s = tostring(fallback or "") end
		return s
	end

	local function NowMsSafe(v)
		local n = tonumber(v)
		if n ~= nil and n > 0 then return math.floor(n + 0.0) end
		return math.floor(os.time() * 1000)
	end

	DB.Chat = DB.Chat or {}

	function DB.Chat.UpsertConversation(ownerPid, convId, appId, title, lastPreview, lastAtMs, unreadDelta)
		EnsureReady()

		local pid = tostring(ownerPid or "")
		local cid = tostring(convId or "")
		if pid == "" or cid == "" then return false end

		local a = SafeText(appId, "chat")
		local t = SafeText(title, "Chat")
		local preview = tostring(lastPreview or "")
		local lastAt = NowMsSafe(lastAtMs)
		local now = NowMsSafe()
		local delta = ClampInt(unreadDelta, -1000000, 1000000, 0)

		local existing = Database.Select([[
			SELECT UnreadCount
			FROM ChatConversations
			WHERE OwnerPid = ? AND ConvId = ?
			LIMIT 1
		]], { pid, cid })

		local ex = RowsFirst(existing)
		if not ex then
			local unread = delta
			if unread < 0 then unread = 0 end

			return Database.Execute([[
				INSERT INTO ChatConversations (
					OwnerPid, ConvId, AppId, Title,
					LastMsgAt, LastMsgPreview,
					UnreadCount,
					UpdatedAt
				) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
			]], {
				pid, cid, a, t,
				lastAt, preview,
				unread,
				now
			}) == true
		end

		local curUnread = tonumber(DB.RowGet(ex, "UnreadCount", "unreadcount")) or 0
		local nextUnread = curUnread + delta
		if nextUnread < 0 then nextUnread = 0 end

		return Database.Execute([[
			UPDATE ChatConversations SET
				AppId = ?,
				Title = ?,
				LastMsgAt = ?,
				LastMsgPreview = ?,
				UnreadCount = ?,
				UpdatedAt = ?
			WHERE OwnerPid = ? AND ConvId = ?
		]], {
			a,
			t,
			lastAt,
			preview,
			nextUnread,
			now,
			pid,
			cid
		}) == true
	end

	function DB.Chat.InsertMessage(ownerPid, convId, msgId, createdAtMs, sender, text, metaJson)
		EnsureReady()

		local pid = tostring(ownerPid or "")
		local cid = tostring(convId or "")
		local mid = tostring(msgId or "")
		local body = tostring(text or "")

		if pid == "" or cid == "" or mid == "" or body == "" then
			return { ok = false, error = "invalid_payload" }
		end

		local at = NowMsSafe(createdAtMs)
		local snd = SafeText(sender, "system")
		local meta = metaJson ~= nil and tostring(metaJson) or nil

		local ok = Database.Execute([[
			INSERT INTO ChatMessages (
				OwnerPid, ConvId, MsgId,
				CreatedAt, Sender, Text,
				MetaJson
			) VALUES (?, ?, ?, ?, ?, ?, ?)
		]], {
			pid, cid, mid,
			at, snd, body,
			meta
		})

		local rows2 = Database.Select([[
			SELECT MsgId
			FROM ChatMessages
			WHERE OwnerPid = ? AND ConvId = ? AND MsgId = ?
			LIMIT 1
		]], { pid, cid, mid })

		local exists = RowsCount(rows2) > 0
		if exists ~= true then
			return { ok = false, error = "db_insert_failed" }
		end

		return { ok = true }
	end

	function DB.Chat.ListConversations(ownerPid, limit, offset)
		EnsureReady()

		local pid = tostring(ownerPid or "")
		if pid == "" then return {} end

		local lim = ClampInt(limit, 1, 200, 50)
		local off = ClampInt(offset, 0, 1000000, 0)

		local rows = Database.Select([[
			SELECT
				OwnerPid, ConvId,
				AppId, Title,
				LastMsgAt, LastMsgPreview,
				UnreadCount,
				UpdatedAt
			FROM ChatConversations
			WHERE OwnerPid = ?
			ORDER BY LastMsgAt DESC
			LIMIT ? OFFSET ?
		]], { pid, lim, off })

		local out = {}
		local n = RowsCount(rows)
		for i = 1, n do
			local r = RowAt(rows, i)
			out[#out + 1] = {
				ownerPid = tostring(DB.RowGet(r, "OwnerPid", "ownerpid") or pid),
				convId = tostring(DB.RowGet(r, "ConvId", "convid") or ""),
				appId = tostring(DB.RowGet(r, "AppId", "appid") or "chat"),
				title = tostring(DB.RowGet(r, "Title", "title") or "Chat"),
				lastMsgAt = tonumber(DB.RowGet(r, "LastMsgAt", "lastmsgat") or 0) or 0,
				lastMsgPreview = tostring(DB.RowGet(r, "LastMsgPreview", "lastmsgpreview") or ""),
				unreadCount = tonumber(DB.RowGet(r, "UnreadCount", "unreadcount") or 0) or 0,
				updatedAt = tonumber(DB.RowGet(r, "UpdatedAt", "updatedat") or 0) or 0,
			}
		end

		return out
	end

	function DB.Chat.ListMessages(ownerPid, convId, limit, beforeAtMs)
		EnsureReady()

		local pid = tostring(ownerPid or "")
		local cid = tostring(convId or "")
		if pid == "" or cid == "" then return {} end

		local lim = ClampInt(limit, 1, 200, 50)
		local before = tonumber(beforeAtMs)

		local rows
		if before ~= nil and before > 0 then
			rows = Database.Select([[
				SELECT
					MsgId, CreatedAt, Sender, Text, MetaJson
				FROM ChatMessages
				WHERE OwnerPid = ? AND ConvId = ? AND CreatedAt < ?
				ORDER BY CreatedAt DESC
				LIMIT ?
			]], { pid, cid, before, lim })
		else
			rows = Database.Select([[
				SELECT
					MsgId, CreatedAt, Sender, Text, MetaJson
				FROM ChatMessages
				WHERE OwnerPid = ? AND ConvId = ?
				ORDER BY CreatedAt DESC
				LIMIT ?
			]], { pid, cid, lim })
		end

		local out = {}
		local n = RowsCount(rows)
		for i = 1, n do
			local r = RowAt(rows, i)
			out[#out + 1] = {
				msgId = tostring(DB.RowGet(r, "MsgId", "msgid") or ""),
				createdAt = tonumber(DB.RowGet(r, "CreatedAt", "createdat") or 0) or 0,
				sender = tostring(DB.RowGet(r, "Sender", "sender") or "system"),
				text = tostring(DB.RowGet(r, "Text", "text") or ""),
				metaJson = DB.RowGet(r, "MetaJson", "metajson"),
			}
		end

		return out
	end

	function DB.Chat.MarkRead(ownerPid, convId)
		EnsureReady()

		local pid = tostring(ownerPid or "")
		local cid = tostring(convId or "")
		if pid == "" or cid == "" then return false end

		local now = NowMsSafe()

		return Database.Execute([[
			UPDATE ChatConversations SET
				UnreadCount = 0,
				UpdatedAt = ?
			WHERE OwnerPid = ? AND ConvId = ?
		]], { now, pid, cid }) == true
	end

	function DB.Chat.TrimConversation(ownerPid, convId, maxMessages)
		EnsureReady()

		local pid = tostring(ownerPid or "")
		local cid = tostring(convId or "")
		if pid == "" or cid == "" then return false end

		local keep = ClampInt(maxMessages, 10, 5000, 500)

		local ok = Database.Execute([[
			DELETE FROM ChatMessages
			WHERE OwnerPid = ? AND ConvId = ?
			AND rowid NOT IN (
				SELECT rowid
				FROM ChatMessages
				WHERE OwnerPid = ? AND ConvId = ?
				ORDER BY CreatedAt DESC
				LIMIT ?
			)
		]], { pid, cid, pid, cid, keep })

		return ok == true
	end

	function DB.Chat.AddIncoming(ownerPid, convId, appId, title, msgId, createdAtMs, sender, text, metaJson, isReadNow, trimMax)
		EnsureReady()

		local pid = tostring(ownerPid or "")
		local cid = tostring(convId or "")
		if pid == "" or cid == "" then
			return { ok = false, error = "invalid_payload" }
		end

		local at = NowMsSafe(createdAtMs)
		local ins = DB.Chat.InsertMessage(pid, cid, msgId, at, sender, text, metaJson)
		if not ins or ins.ok ~= true then
			return ins or { ok = false, error = "db_insert_failed" }
		end

		local delta = (isReadNow == true) and 0 or 1
		DB.Chat.UpsertConversation(pid, cid, appId, title, text, at, delta)

		local keep = trimMax ~= nil and ClampInt(trimMax, 10, 5000, 500) or 500
		DB.Chat.TrimConversation(pid, cid, keep)

		return { ok = true }
	end

	return DB
end

return Apply
