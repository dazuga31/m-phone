local Core = require("core_adapter")
local VoiceAdapter = require("voice_adapter")

local Communications = {}

local function Trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function DigitsOnly(value)
	return tostring(value or ""):gsub("%D", "")
end

local function NowMs()
	return math.floor(os.time() * 1000)
end

local function ConfigValue(key, fallback)
	local communications = Config and Config.Communications or {}
	return communications[key] ~= nil and communications[key] or fallback
end

local function IsValidPhoneNumber(value)
	local phone = DigitsOnly(value)
	local digits = math.max(4, math.floor(tonumber(ConfigValue("PhoneNumberDigits", 6)) or 6))
	return #phone == digits and phone or nil
end

local function GeneratePhoneNumber()
	local digits = math.max(4, math.floor(tonumber(ConfigValue("PhoneNumberDigits", 6)) or 6))
	return tostring(math.random(10 ^ (digits - 1), (10 ^ digits) - 1))
end

local function Reply(controller, requestId, kind, ok, data, err)
	TriggerClientEvent(controller, "m-phone:communicationsResult", {
		requestId = tostring(requestId or ""), kind = tostring(kind or "unknown"),
		ok = ok == true, data = data, error = err, meta = { timestamp = NowMs() },
	})
end

function Communications.Setup(options)
	local DB = assert(options.DB, "communications DB is required")
	local GetPlayerId = assert(options.GetPlayerId, "GetPlayerId is required")
	local LogInfo = options.LogInfo or function() end
	local LogWarn = options.LogWarn or function() end
	local rateWindows = {}
	local activeCalls = {}
	local callByPlayer = {}
	local voice = VoiceAdapter.New({
		Config = ConfigValue("Voice", {}),
		LogInfo = LogInfo,
		LogWarn = LogWarn,
	})
	LogInfo("communications voice initialized", {
		enabled = voice:IsEnabled(),
		provider = tostring(ConfigValue("Voice", {}).Provider or "helix"),
	})

	local function ProfileTable(row)
		return DB.Communications.ProfileToTable(row)
	end

	local function EnsureProfile(controller)
		local playerId = tostring(GetPlayerId(controller) or "")
		if playerId == "" then return nil, "player_not_found" end
		local snapshot, snapshotError = Core.GetPlayer(controller)
		if not snapshot then return nil, snapshotError or "core_player_not_found" end
		if snapshot.citizenId == "" then return nil, "citizen_id_missing" end

		local existing = ProfileTable(DB.Communications.GetProfileByPlayerId(playerId))
		if existing then
			if Core.GetPhoneNumber(snapshot) ~= existing.phoneNumber then
				local ok, err = Core.SetPhoneNumber(snapshot, existing.phoneNumber)
				if not ok then LogWarn("phone metadata sync failed", { error = err, playerId = playerId }) end
			end
			DB.Communications.UpsertProfile(playerId, snapshot.citizenId, existing.phoneNumber, snapshot.name)
			existing.displayName = snapshot.name
			return existing
		end

		local selected = IsValidPhoneNumber(Core.GetPhoneNumber(snapshot))
		if selected then
			local owner = ProfileTable(DB.Communications.GetProfileByPhone(selected))
			if owner and owner.citizenId ~= snapshot.citizenId then selected = nil end
		end
		for _ = 1, 100 do
			if selected then break end
			local candidate = GeneratePhoneNumber()
			if not DB.Communications.GetProfileByPhone(candidate) then selected = candidate end
		end
		if not selected then return nil, "phone_number_pool_exhausted" end
		if not DB.Communications.UpsertProfile(playerId, snapshot.citizenId, selected, snapshot.name) then return nil, "phone_profile_write_failed" end
		local okMetadata, metadataError = Core.SetPhoneNumber(snapshot, selected)
		if not okMetadata then LogWarn("phone metadata write failed", { playerId = playerId, error = metadataError }) end
		LogInfo("phone profile assigned", {
			playerId = playerId,
			citizenId = snapshot.citizenId,
			phoneNumber = selected,
			metadataSynced = okMetadata == true,
		})
		return { playerId = playerId, citizenId = snapshot.citizenId, phoneNumber = selected, displayName = snapshot.name }
	end

	local function OnlineController(profile)
		if not profile then return nil end
		local online = Core.GetPlayerByCitizenId(profile.citizenId)
		return online and online.controller or nil
	end

	local function ConversationTitle(ownerPlayerId, otherProfile)
		local savedName = DB.Communications.ContactName(ownerPlayerId, otherProfile.phoneNumber)
		if savedName ~= "" then return savedName end
		return otherProfile.displayName ~= "" and otherProfile.displayName or otherProfile.phoneNumber
	end

	local function RateLimit(playerId)
		local now = NowMs()
		local windowMs = math.max(1000, tonumber(ConfigValue("RateLimitWindowSeconds", 10)) * 1000)
		local maximum = math.max(1, tonumber(ConfigValue("RateLimitMessages", 8)) or 8)
		local state = rateWindows[playerId]
		if not state or now - state.startedAt >= windowMs then
			rateWindows[playerId] = { startedAt = now, count = 1 }
			return true
		end
		if state.count >= maximum then return false end
		state.count = state.count + 1
		return true
	end

	local function Encode(value)
		if json and type(json.encode) == "function" then
			local ok, encoded = pcall(json.encode, value)
			if ok then return encoded end
		end
		if JSON and type(JSON.stringify) == "function" then
			local ok, encoded = pcall(JSON.stringify, value)
			if ok then return encoded end
		end
		return nil
	end

	local function StoreDirectMessage(sender, recipient, text, createdAt, messageId, status, metaJson)
		local senderConv = "sms:" .. recipient.phoneNumber
		local recipientConv = "sms:" .. sender.phoneNumber
		local senderTitle = ConversationTitle(sender.playerId, recipient)
		local recipientTitle = ConversationTitle(recipient.playerId, sender)
		local senderResult = DB.Chat.AddIncoming(sender.playerId, senderConv, "chat", senderTitle, messageId .. ":out", createdAt, "me", text, metaJson, true, 500)
		if not senderResult or senderResult.ok ~= true then return false, "sender_message_write_failed" end
		local recipientResult = DB.Chat.AddIncoming(recipient.playerId, recipientConv, "chat", recipientTitle, messageId .. ":in", createdAt, sender.displayName, text, metaJson, false, 500)
		if not recipientResult or recipientResult.ok ~= true then return false, "recipient_message_write_failed" end
		if not DB.Communications.CreateSmsReceipt(messageId, sender.playerId, recipient.playerId, senderConv, recipientConv, status, createdAt) then
			return false, "receipt_write_failed"
		end
		return true, nil, { senderConvId = senderConv, recipientConvId = recipientConv, senderTitle = senderTitle, recipientTitle = recipientTitle }
	end

	local function ContactPayload(profile)
		local contacts = DB.Communications.ListContacts(profile.playerId)
		for _, systemContact in ipairs(ConfigValue("SystemContacts", {})) do
			contacts[#contacts + 1] = {
				id = tostring(systemContact.id or ("system:" .. tostring(systemContact.phoneNumber or ""))),
				name = tostring(systemContact.name or "Service"), phoneNumber = tostring(systemContact.phoneNumber or ""),
				category = tostring(systemContact.category or "system"), isSystem = true, isFavorite = true, isBlocked = false,
			}
		end
		return contacts
	end

	local function PersistCall(call)
		local endedAt = call.endedAt or 0
		local duration = call.answeredAt and call.answeredAt > 0 and endedAt > 0 and math.max(0, math.floor((endedAt - call.answeredAt) / 1000)) or 0
		DB.Communications.AddCallHistory({ callId = call.id, ownerPlayerId = call.caller.playerId, peerPhoneNumber = call.recipient.phoneNumber, peerDisplayName = call.recipient.displayName, direction = "outgoing", status = call.status, startedAt = call.startedAt, answeredAt = call.answeredAt or 0, endedAt = endedAt, durationSeconds = duration })
		DB.Communications.AddCallHistory({ callId = call.id, ownerPlayerId = call.recipient.playerId, peerPhoneNumber = call.caller.phoneNumber, peerDisplayName = call.caller.displayName, direction = "incoming", status = call.recipientStatus or call.status, startedAt = call.startedAt, answeredAt = call.answeredAt or 0, endedAt = endedAt, durationSeconds = duration })
	end

	local function FinishCall(call, status, actorPlayerId)
		if not call or call.endedAt then return false end
		local hadVoiceConnected = call.voiceConnected == true
		local callerController = OnlineController(call.caller) or call.callerController
		local recipientController = OnlineController(call.recipient) or call.recipientController
		voice:Disconnect(call, callerController, recipientController)
		call.status = status or "ended"
		call.recipientStatus = call.status == "cancelled" and "missed" or call.status
		call.endedAt = NowMs()
		callByPlayer[call.caller.playerId] = nil
		callByPlayer[call.recipient.playerId] = nil
		activeCalls[call.id] = nil
		PersistCall(call)
		local sharedPayload = { callId = call.id, actorPlayerId = actorPlayerId, endedAt = call.endedAt, signalingOnly = not hadVoiceConnected, voiceConnected = false }
		local callerPayload = {
			callId = sharedPayload.callId, actorPlayerId = sharedPayload.actorPlayerId, endedAt = sharedPayload.endedAt, signalingOnly = sharedPayload.signalingOnly, voiceConnected = false,
			status = call.status, phoneNumber = call.recipient.phoneNumber, displayName = ConversationTitle(call.caller.playerId, call.recipient),
		}
		local recipientPayload = {
			callId = sharedPayload.callId, actorPlayerId = sharedPayload.actorPlayerId, endedAt = sharedPayload.endedAt, signalingOnly = sharedPayload.signalingOnly, voiceConnected = false,
			status = call.recipientStatus or call.status, phoneNumber = call.caller.phoneNumber, displayName = ConversationTitle(call.recipient.playerId, call.caller),
		}
		if callerController then TriggerClientEvent(callerController, "m-phone:call:state", callerPayload) end
		if recipientController then TriggerClientEvent(recipientController, "m-phone:call:state", recipientPayload) end
		return true
	end

	RegisterServerEvent("m-phone:communicationsGetProfile", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b)
		local profile, err = EnsureProfile(controller)
		Reply(controller, type(payload) == "table" and payload.requestId or "", "profile", profile ~= nil, profile, err)
	end)

	RegisterServerEvent("m-phone:contactsList", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b)
		local profile, err = EnsureProfile(controller)
		Reply(controller, type(payload) == "table" and payload.requestId or "", "contactsList", profile ~= nil, profile and ContactPayload(profile) or nil, err)
	end)

	RegisterServerEvent("m-phone:contactsSave", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b); payload = type(payload) == "table" and payload or {}
		local profile, err = EnsureProfile(controller)
		if not profile then Reply(controller, payload.requestId, "contactsSave", false, nil, err) return end
		local name, phone = Trim(payload.name), IsValidPhoneNumber(payload.phoneNumber)
		if name == "" or #name > math.max(8, tonumber(ConfigValue("MaxContactNameLength", 48)) or 48) then Reply(controller, payload.requestId, "contactsSave", false, nil, "invalid_contact_name") return end
		if not phone then Reply(controller, payload.requestId, "contactsSave", false, nil, "invalid_phone_number") return end
		if phone == profile.phoneNumber then Reply(controller, payload.requestId, "contactsSave", false, nil, "cannot_add_self") return end
		if not DB.Communications.GetProfileByPhone(phone) then Reply(controller, payload.requestId, "contactsSave", false, nil, "phone_number_not_found") return end
		if DB.Communications.ContactName(profile.playerId, phone) == "" and DB.Communications.CountContacts(profile.playerId) >= math.max(1, tonumber(ConfigValue("MaxContacts", 250)) or 250) then Reply(controller, payload.requestId, "contactsSave", false, nil, "contacts_limit_reached") return end
		local contactId = "contact:" .. phone
		local ok = DB.Communications.UpsertContact(profile.playerId, contactId, name, phone)
		local flags = DB.Communications.GetContactFlags(profile.playerId, phone)
		Reply(controller, payload.requestId, "contactsSave", ok, { id = contactId, name = name, phoneNumber = phone, isFavorite = flags.isFavorite, isBlocked = flags.isBlocked }, ok and nil or "contact_write_failed")
	end)

	RegisterServerEvent("m-phone:contactsDelete", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b); payload = type(payload) == "table" and payload or {}
		local profile, err = EnsureProfile(controller)
		if not profile then Reply(controller, payload.requestId, "contactsDelete", false, nil, err) return end
		local contactId = Trim(payload.contactId)
		local ok = contactId ~= "" and DB.Communications.DeleteContact(profile.playerId, contactId)
		Reply(controller, payload.requestId, "contactsDelete", ok == true, { contactId = contactId }, ok and nil or "contact_delete_failed")
	end)

	RegisterServerEvent("m-phone:contactsSetFlags", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b); payload = type(payload) == "table" and payload or {}
		local profile, err = EnsureProfile(controller)
		if not profile then Reply(controller, payload.requestId, "contactsSetFlags", false, nil, err) return end
		local phone = IsValidPhoneNumber(payload.phoneNumber)
		if not phone then Reply(controller, payload.requestId, "contactsSetFlags", false, nil, "invalid_phone_number") return end
		local current = DB.Communications.GetContactFlags(profile.playerId, phone)
		local favorite = payload.isFavorite == nil and current.isFavorite or payload.isFavorite == true
		local blocked = payload.isBlocked == nil and current.isBlocked or payload.isBlocked == true
		local ok = DB.Communications.SetContactFlags(profile.playerId, phone, favorite, blocked)
		Reply(controller, payload.requestId, "contactsSetFlags", ok, { phoneNumber = phone, isFavorite = favorite, isBlocked = blocked }, ok and nil or "contact_flags_write_failed")
	end)

	RegisterServerEvent("m-phone:smsSend", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b); payload = type(payload) == "table" and payload or {}
		local sender, err = EnsureProfile(controller)
		if not sender then Reply(controller, payload.requestId, "smsSend", false, nil, err) return end
		local recipientPhone, text = IsValidPhoneNumber(payload.phoneNumber), Trim(payload.text)
		local photoId = Trim(payload.photoId)
		if not recipientPhone then Reply(controller, payload.requestId, "smsSend", false, nil, "invalid_phone_number") return end
		if recipientPhone == sender.phoneNumber then Reply(controller, payload.requestId, "smsSend", false, nil, "cannot_message_self") return end
		if text == "" and photoId == "" then Reply(controller, payload.requestId, "smsSend", false, nil, "empty_message") return end
		if #text > math.max(1, tonumber(ConfigValue("MaxMessageLength", 500)) or 500) then Reply(controller, payload.requestId, "smsSend", false, nil, "message_too_long") return end
		if not RateLimit(sender.playerId) then Reply(controller, payload.requestId, "smsSend", false, nil, "rate_limited") return end
		local attachment, metaJson = nil, nil
		if photoId ~= "" then
			local photo = DB.Photos and DB.Photos.Get(sender.playerId, photoId) or nil
			if not photo or tostring(photo.url or "") == "" then Reply(controller, payload.requestId, "smsSend", false, nil, "photo_not_found") return end
			attachment = { type = "image", photoId = photo.id, url = photo.url, width = photo.width, height = photo.height, source = photo.source }
			metaJson = Encode({ attachments = { attachment } })
			if not metaJson then Reply(controller, payload.requestId, "smsSend", false, nil, "attachment_encode_failed") return end
		end
		local recipient = ProfileTable(DB.Communications.GetProfileByPhone(recipientPhone))
		if not recipient then Reply(controller, payload.requestId, "smsSend", false, nil, "phone_number_not_found") return end
		if DB.Communications.IsBlocked(recipient.playerId, sender.phoneNumber) then Reply(controller, payload.requestId, "smsSend", false, nil, "recipient_unavailable") return end
		local recipientController = OnlineController(recipient)
		local createdAt, messageId = NowMs(), ("sms|%s|%s"):format(tostring(NowMs()), tostring(math.random(1000, 9999)))
		local status = recipientController and "delivered" or "sent"
		local stored, storeError, conversations = StoreDirectMessage(sender, recipient, text ~= "" and text or "Photo", createdAt, messageId, status, metaJson)
		if not stored then Reply(controller, payload.requestId, "smsSend", false, nil, storeError) return end
		if recipientController then TriggerClientEvent(recipientController, "m-phone:chat:directMessage", { chatId = conversations.recipientConvId, chatName = conversations.recipientTitle, phoneNumber = sender.phoneNumber, sender = sender.displayName, text = text ~= "" and text or "Photo", attachments = attachment and { attachment } or {}, createdAt = createdAt, msgId = messageId .. ":in" }) end
		Reply(controller, payload.requestId, "smsSend", true, { convId = conversations.senderConvId, msgId = messageId .. ":out", messageId = messageId, createdAt = createdAt, recipient = recipientPhone, status = status }, nil)
	end)

	RegisterServerEvent("m-phone:callsList", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b); payload = type(payload) == "table" and payload or {}
		local profile, err = EnsureProfile(controller)
		if not profile then Reply(controller, payload.requestId, "callsList", false, nil, err) return end
		Reply(controller, payload.requestId, "callsList", true, DB.Communications.ListCallHistory(profile.playerId, payload.limit, payload.offset), nil)
	end)

	RegisterServerEvent("m-phone:callStart", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b); payload = type(payload) == "table" and payload or {}
		local caller, err = EnsureProfile(controller)
		if not caller then Reply(controller, payload.requestId, "callStart", false, nil, err) return end
		local targetPhone = IsValidPhoneNumber(payload.phoneNumber)
		local recipient = targetPhone and ProfileTable(DB.Communications.GetProfileByPhone(targetPhone)) or nil
		if not recipient or targetPhone == caller.phoneNumber then Reply(controller, payload.requestId, "callStart", false, nil, "invalid_recipient") return end
		if DB.Communications.IsBlocked(recipient.playerId, caller.phoneNumber) then Reply(controller, payload.requestId, "callStart", false, nil, "recipient_unavailable") return end
		local recipientSettings = DB.GetSettings(recipient.playerId) or {}
		local callerFlags = DB.Communications.GetContactFlags(recipient.playerId, caller.phoneNumber) or {}
		local favoriteBypass = recipientSettings.allowFavoriteCalls ~= false and callerFlags.isFavorite == true
		if recipientSettings.doNotDisturb == true and not favoriteBypass then
			local call = { id = ("call|%s|%s"):format(tostring(NowMs()), tostring(math.random(1000, 9999))), caller = caller, recipient = recipient, startedAt = NowMs(), endedAt = NowMs(), status = "unavailable", recipientStatus = "silenced" }
			PersistCall(call)
			Reply(controller, payload.requestId, "callStart", false, { callId = call.id, status = "unavailable" }, "recipient_do_not_disturb")
			return
		end
		if callByPlayer[caller.playerId] or callByPlayer[recipient.playerId] then Reply(controller, payload.requestId, "callStart", false, nil, "line_busy") return end
		local recipientController = OnlineController(recipient)
		local call = {
			id = ("call|%s|%s"):format(tostring(NowMs()), tostring(math.random(1000, 9999))),
			caller = caller,
			recipient = recipient,
			callerController = controller,
			recipientController = recipientController,
			startedAt = NowMs(),
			status = recipientController and "ringing" or "unavailable",
		}
		if not recipientController then
			call.endedAt = NowMs(); call.recipientStatus = "missed"; PersistCall(call)
			Reply(controller, payload.requestId, "callStart", false, { callId = call.id, status = "unavailable" }, "recipient_offline")
			return
		end
		activeCalls[call.id], callByPlayer[caller.playerId], callByPlayer[recipient.playerId] = call, call.id, call.id
		TriggerClientEvent(recipientController, "m-phone:call:incoming", { callId = call.id, phoneNumber = caller.phoneNumber, displayName = ConversationTitle(recipient.playerId, caller), startedAt = call.startedAt, signalingOnly = true })
		Reply(controller, payload.requestId, "callStart", true, { callId = call.id, phoneNumber = recipient.phoneNumber, displayName = ConversationTitle(caller.playerId, recipient), status = "ringing", startedAt = call.startedAt, signalingOnly = true }, nil)
		if Timer and type(Timer.SetTimeout) == "function" then Timer.SetTimeout(function() if activeCalls[call.id] and call.status == "ringing" then FinishCall(call, "missed", "system") end end, math.max(5, tonumber(ConfigValue("CallRingTimeoutSeconds", 30)) or 30) * 1000) end
	end)

	RegisterServerEvent("m-phone:callAction", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b); payload = type(payload) == "table" and payload or {}
		local profile, err = EnsureProfile(controller)
		if not profile then Reply(controller, payload.requestId, "callAction", false, nil, err) return end
		local call = activeCalls[tostring(payload.callId or "")]
		if not call or (call.caller.playerId ~= profile.playerId and call.recipient.playerId ~= profile.playerId) then Reply(controller, payload.requestId, "callAction", false, nil, "call_not_found") return end
		local action = tostring(payload.action or "")
		if action == "accept" and profile.playerId == call.recipient.playerId and call.status == "ringing" then
			local callerController = OnlineController(call.caller)
			if not callerController then
				FinishCall(call, "failed", profile.playerId)
				Reply(controller, payload.requestId, "callAction", false, nil, "caller_offline")
				return
			end
			local voiceConnected = false
			if voice:IsEnabled() then
				local voiceError
				voiceConnected, voiceError = voice:Connect(call, callerController, controller)
				if not voiceConnected then
					LogWarn("call voice connection failed", { callId = call.id, error = voiceError })
					FinishCall(call, "failed", profile.playerId)
					Reply(controller, payload.requestId, "callAction", false, nil, voiceError or "voice_connection_failed")
					return
				end
			end
			call.status, call.answeredAt = "connected", NowMs()
			local state = { callId = call.id, status = "connected", answeredAt = call.answeredAt, signalingOnly = not voiceConnected, voiceConnected = voiceConnected }
			TriggerClientEvent(callerController, "m-phone:call:state", state)
			TriggerClientEvent(controller, "m-phone:call:state", state)
			Reply(controller, payload.requestId, "callAction", true, state, nil)
			return
		end
		if action == "mute" and call.status == "connected" then
			local muted = payload.muted == true
			local mutedOk, mutedError = voice:SetMuted(call, controller, muted)
			if not mutedOk then
				Reply(controller, payload.requestId, "callAction", false, nil, mutedError or "voice_mute_failed")
				return
			end
			local state = { callId = call.id, status = "connected", voiceConnected = true, voiceMuted = muted }
			TriggerClientEvent(controller, "m-phone:call:state", state)
			Reply(controller, payload.requestId, "callAction", true, state, nil)
			return
		end
		if action == "reject" then FinishCall(call, "rejected", profile.playerId); Reply(controller, payload.requestId, "callAction", true, { callId = call.id, status = "rejected" }, nil) return end
		if action == "end" then FinishCall(call, call.status == "ringing" and "cancelled" or "ended", profile.playerId); Reply(controller, payload.requestId, "callAction", true, { callId = call.id, status = "ended" }, nil) return end
		Reply(controller, payload.requestId, "callAction", false, nil, "invalid_call_action")
	end)

	RegisterServerEvent("m-phone:callVoiceActivity", function(a, b)
		local controller, payload = options.ResolveControllerAndPayload(a, b); payload = type(payload) == "table" and payload or {}
		local profile = EnsureProfile(controller)
		if not profile then return end
		local call = activeCalls[tostring(payload.callId or "")]
		if not call or call.status ~= "connected" then return end
		if call.caller.playerId ~= profile.playerId and call.recipient.playerId ~= profile.playerId then return end

		local recipientController
		if call.caller.playerId == profile.playerId then
			recipientController = OnlineController(call.recipient) or call.recipientController
		else
			recipientController = OnlineController(call.caller) or call.callerController
		end
		if recipientController then
			TriggerClientEvent(recipientController, "m-phone:call:voiceActivity", {
				callId = call.id,
				participant = "remote",
				talking = payload.talking == true,
			})
		end
	end)

	local function HandlePlayerUnload(controller)
		local playerId = tostring(GetPlayerId(controller) or "")
		local callId = playerId ~= "" and callByPlayer[playerId] or nil
		local call = callId and activeCalls[callId] or nil
		if not call then
			for _, candidate in pairs(activeCalls) do
				if candidate.callerController == controller or candidate.recipientController == controller then
					call = candidate
					break
				end
			end
		end
		if call then FinishCall(call, "disconnected", playerId) end
	end

	RegisterServerEvent("HEvent:PlayerUnloaded", function(controller)
		HandlePlayerUnload(controller)
	end)

	RegisterServerEvent("QBCore:Server:OnPlayerUnload", function(controller)
		HandlePlayerUnload(controller)
	end)

	local function MarkConversationRead(controller, convId)
		local profile = EnsureProfile(controller)
		if not profile or not tostring(convId or ""):match("^sms:") then return {} end
		local updated = DB.Communications.MarkSmsRead(profile.playerId, tostring(convId), NowMs())
		for _, receipt in ipairs(updated) do
			local senderProfile = ProfileTable(DB.Communications.GetProfileByPlayerId(receipt.senderPlayerId))
			local senderController = OnlineController(senderProfile)
			if senderController then TriggerClientEvent(senderController, "m-phone:sms:status", { messageId = receipt.messageId, convId = receipt.senderConvId, status = "read", readAt = NowMs() }) end
		end
		return updated
	end

	local function Shutdown()
		local calls = {}
		for _, call in pairs(activeCalls) do calls[#calls + 1] = call end
		for _, call in ipairs(calls) do FinishCall(call, "shutdown", "system") end
	end

	return { EnsureProfile = EnsureProfile, MarkConversationRead = MarkConversationRead, Shutdown = Shutdown, Core = Core }
end

return Communications
