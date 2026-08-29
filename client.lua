	-- m-phone/client.lua (CORE + LOADER)
	-- BUILD=2026-01-01-client-core-hud-v1

	-- =========================
	-- State
	-- =========================

	local UI = nil
	local HUD = nil
	local isOpen = false

	local UI_URL = "m-phone/web/index.html"
	local Shared = require("client_shared")
	local SpatialWebUI = require("Desktop.spatial_webui")
	local PhoneSDK = require("AppSDK.client")
	local WidgetSDK = require("WidgetSDK.client")
	local function FeatureEnabled(name)
		return not Config or not Config.IsFeatureEnabled or Config.IsFeatureEnabled(name)
	end
	local CreatorLink = nil
	if FeatureEnabled("CreatorLink") then
		local creatorLinkOk, creatorLinkModule = pcall(require, "PhoneApps.CreatorLink.client")
		if creatorLinkOk then CreatorLink = creatorLinkModule
		else print("[m-phone][client][error] CreatorLink load failed: " .. tostring(creatorLinkModule)) end
	end

	-- =========================
	-- Logger (Lua -> WebUI)
	-- =========================

	local function Notify(level, msg, tag, extra, duration)
		Shared.Notify(level, msg, tag, extra, duration)
	end

	local function Log(level, msg, tag, extra) Shared.Notify(level, msg, tag, extra) end
	local function LogInfo(msg, tag, extra) Log("info", msg, tag, extra) end
	local function LogWarn(msg, tag, extra) Log("warn", msg, tag, extra) end
	local function LogErr(msg, tag, extra)  Log("error", msg, tag, extra) end
	local function LogDbg(msg, tag, extra)  Log("debug", msg, tag, extra) end
	local function LogOk(msg, tag, extra)   Log("success", msg, tag, extra) end

	-- =========================
	-- Helpers (WebUI fan-out)
	-- =========================

	local function SendToUI(target, eventName, payload)
		return Shared.SendToUI(target, eventName, payload)
	end

	local function SendToUIs(eventName, payload)
		Shared.SendToUIs(HUD, UI, eventName, payload)
	end

	local function ResolvePlayerController()
		return Shared.ResolvePlayerController(HUD)
	end


	-- =========================
	-- Input block while WebUI is open (HELIX)
	-- =========================

	local uiTyping = false

	local function TryCall(fn, ...)
		return Shared.TryCall(fn, ...)
	end

	local function SetGameInputBlocked(blocked)
		blocked = blocked == true

		-- 1) WebUI input mode: "UI only" якщо підтримується, інакше fallback
		if UI then
			local ok = pcall(function()
				UI:SetInputMode(blocked and 2 or 0)
			end)
			if not ok then
				UI:SetInputMode(blocked and 1 or 0)
			end
		end

		-- 2) Safe-probing API (може не існувати в конкретному білді)
		TryCall(Input and Input.SetEnabled, not blocked)
		TryCall(Input and Input.SetGameInputEnabled, not blocked)
		TryCall(Input and Input.SetIgnoreGameInput, blocked)

		-- 3) PlayerController safe-probing
		local pc = GetPlayerController and GetPlayerController() or nil
		if pc then
			TryCall(pc.SetIgnoreMoveInput, pc, blocked)
			TryCall(pc.SetIgnoreLookInput, pc, blocked)
		end
	end


	-- =========================
	-- Animation
	-- =========================

	local ACTIONS_PREFIX = "/Game/Characters/Heroes/Unified/Animations/Actions/"
	local PHONE_ANIM_INTRO = ACTIONS_PREFIX .. "Phone/A_Scroll_Mobile_Intro.A_Scroll_Mobile_Intro"
	local PHONE_ANIM_LOOP = ACTIONS_PREFIX .. "Phone/A_Scroll_Mobile_Loop.A_Scroll_Mobile_Loop"
	local PHONE_ANIM_OUTRO = ACTIONS_PREFIX .. "Phone/A_Scroll_Mobile_Outro.A_Scroll_Mobile_Outro"
	local phoneUseActive = false
	local phoneUseGeneration = 0

	local function MakePlayAnimParams()
		LogDbg("Anim params probe", "m-phone", {
			hasUE = UE ~= nil,
			ueType = type(UE),
			ueFHelixPlayAnimParams = UE and type(UE.FHelixPlayAnimParams) or "no_ue",
			globalFHelixPlayAnimParams = type(FHelixPlayAnimParams),
		})

		-- Варіант 1: як у docs
		if UE and type(UE.FHPlayAnimParams) == "function" then
			local ok, result = pcall(function()
				return UE.FHPlayAnimParams()
			end)
			if ok then return result end
		end

		if UE and type(UE.FHelixPlayAnimParams) == "function" then
			local ok, result = pcall(function()
				return UE.FHelixPlayAnimParams()
			end)
			if ok then
				return result
			end
		end

		-- Варіант 2: якщо конструктор винесли в global scope
		if type(FHelixPlayAnimParams) == "function" then
			local ok, result = pcall(function()
				return FHelixPlayAnimParams()
			end)
			if ok then
				return result
			end
		end

		-- Варіант 3: plain table fallback
		return {}
	end

	local function StopAnim()
		local pawn = GetPlayerPawn()
		if not pawn then return end

		if not Animation or type(Animation.Stop) ~= "function" then
			LogWarn("Animation.Stop is unavailable", "m-phone")
			return
		end

		local ok, err = pcall(function()
			Animation.Stop(pawn)
		end)

		if not ok then
			LogWarn("Animation.Stop failed", "m-phone", {
				error = tostring(err)
			})
		end
	end

	local function PlayAnim(animPath, loop, callback)
		local pawn = GetPlayerPawn()
		if not pawn then
			LogWarn("PlayAnim: GetPlayerPawn() is nil", "m-phone")
			return false
		end

		if not Animation or type(Animation.Play) ~= "function" then
			LogErr("Animation.Play is unavailable", "m-phone")
			return false
		end

		local params = MakePlayAnimParams()
		params.LoopCount = loop == true and -1 or 1
		params.AnimSlotName = "UpperBody"

		-- Варіант 1: повна сигнатура
		local ok1, res1 = pcall(function()
			return Animation.Play(pawn, animPath, params, callback or function() end)
		end)

		if ok1 then
			LogDbg("Animation.Play(v1 full) -> " .. tostring(res1), "m-phone", {
				anim = animPath,
				paramsType = type(params)
			})
			return res1 == true
		end

		LogWarn("Animation.Play(v1 full) failed", "m-phone", {
			anim = animPath,
			error = tostring(res1)
		})

		-- Варіант 2: без callback
		local ok2, res2 = pcall(function()
			return Animation.Play(pawn, animPath, params)
		end)

		if ok2 then
			LogDbg("Animation.Play(v2 no-callback) -> " .. tostring(res2), "m-phone", {
				anim = animPath,
				paramsType = type(params)
			})
			return res2 == true
		end

		LogWarn("Animation.Play(v2 no-callback) failed", "m-phone", {
			anim = animPath,
			error = tostring(res2)
		})

		-- Варіант 3: тільки pawn + path
		local ok3, res3 = pcall(function()
			return Animation.Play(pawn, animPath)
		end)

		if ok3 then
			LogDbg("Animation.Play(v3 minimal) -> " .. tostring(res3), "m-phone", {
				anim = animPath
			})
			return res3 == true
		end

		LogErr("Animation.Play failed in all variants", "m-phone", {
			anim = animPath,
			v1 = tostring(res1),
			v2 = tostring(res2),
			v3 = tostring(res3),
		})

		return false
	end

	local function AttachPhoneProp()
		local settings = Config.PhoneUse
		if type(settings) ~= "table" or settings.Enabled == false then return true end
		if type(settings.Attachment) ~= "table" then return false end
		local source = settings.Attachment
		if source.enabled ~= true then return true end
		local attachment = {
			owner = source.owner,
			slot = source.slot,
			mesh = source.mesh,
			bone = source.bone,
			location = {
				x = tonumber(source.location and source.location.x) or 0,
				y = tonumber(source.location and source.location.y) or 0,
				z = tonumber(source.location and source.location.z) or 0,
			},
			rotation = {
				pitch = tonumber(source.rotation and source.rotation.pitch) or 0,
				yaw = tonumber(source.rotation and source.rotation.yaw) or 0,
				roll = tonumber(source.rotation and source.rotation.roll) or 0,
			},
			scale = source.scale,
		}

		local ok, attached, reason = pcall(function()
			return exports["m-attachments"]:Attach(attachment)
		end)
		if not ok or attached ~= true then
			LogWarn("Phone prop attachment failed", "m-phone", {
				error = ok and tostring(reason) or tostring(attached),
			})
			return false
		end
		return true
	end

	local function DetachPhoneProp()
		local settings = Config.PhoneUse
		local attachment = type(settings) == "table" and settings.Attachment or nil
		if type(attachment) ~= "table" or attachment.enabled ~= true then return end
		local owner = type(attachment) == "table" and attachment.owner or "m-phone"
		local slot = type(attachment) == "table" and attachment.slot or "phone"
		pcall(function() exports["m-attachments"]:Detach(owner, slot) end)
	end

	local function BeginPhoneUse()
		if type(Config.PhoneUse) == "table" and Config.PhoneUse.Enabled == false then return end
		phoneUseGeneration = phoneUseGeneration + 1
		local generation = phoneUseGeneration
		phoneUseActive = true
		AttachPhoneProp()
		StopAnim()
		PlayAnim(PHONE_ANIM_INTRO, false, function()
			if phoneUseActive and generation == phoneUseGeneration then
				PlayAnim(PHONE_ANIM_LOOP, true)
			end
		end)
	end

	local function EndPhoneUse(immediate)
		if not phoneUseActive then
			if immediate then DetachPhoneProp() end
			return
		end

		phoneUseActive = false
		phoneUseGeneration = phoneUseGeneration + 1
		local generation = phoneUseGeneration
		StopAnim()
		if immediate then
			DetachPhoneProp()
			return
		end

		local detached = false
		local function Finish()
			if detached then return end
			if phoneUseActive or generation ~= phoneUseGeneration then return end
			detached = true
			DetachPhoneProp()
		end
		if not PlayAnim(PHONE_ANIM_OUTRO, false, Finish) then Finish() end
		if not detached and Timer and type(Timer.SetTimeout) == "function" then
			Timer.SetTimeout(Finish, 1500)
		end
	end

	-- =========================
	-- Visibility / Frame open
	-- =========================

	local function SetVisible(visible)
		isOpen = visible == true

		if not UI then
			LogWarn("SetVisible called but UI is nil", "m-phone")
			return
		end

		UI:SendEvent("setVisible", isOpen)

		-- Block/unblock game input while UI is open
		SetGameInputBlocked(isOpen)

		if isOpen then
			UI:SetInputMode(1)
		else
			if _G.MPhoneCamera and _G.MPhoneCamera.Close then
				pcall(_G.MPhoneCamera.Close)
			end
			UI:SetInputMode(0)
		end
	end

	local function PushInitialData(payload)
		TriggerServerEvent("helix:data:request", payload)
	end

RegisterClientEvent("helix:data:payload", function(data)
	if type(data) ~= "table" then return end

	if Debug == true then
		print("[m-phone][client] RECEIVE helix:data:payload")
		if json and json.encode then print(json.encode(data)) end
	end

	if not UI then
		print("[m-phone][client] UI is nil")
		return
	end

	if Debug == true then print("[m-phone][client] FORWARD -> WebUI") end
	UI:SendEvent("helix:data:payload", data)

	if HUD then
		if Debug == true then print("[m-phone][client] FORWARD -> HUD") end
		HUD:SendEvent("helix:data:payload", data)
	end
end)





	local function OpenFrame(frameEventName, payload)
		if UI then
			UI:SendEvent(frameEventName, payload or {})
			PushInitialData(payload)
		else
			LogWarn("OpenFrame called but UI is nil", "m-phone", { frame = frameEventName })
		end

		SetVisible(true)
	end

	local function CloseUI()
		EndPhoneUse(false)
		SetVisible(false)
	end

	local function TogglePhone()
		LogDbg("TogglePhone", "m-phone")
		if Config.IsFeatureEnabled and not Config.IsFeatureEnabled("Phone") then return end

		if isOpen then
			CloseUI()
			return
		end

		BeginPhoneUse()
		OpenFrame("openPhone")
	end

	local function ToggleTablet()
		LogDbg("ToggleTablet", "m-phone")
		if Config.IsFeatureEnabled and not Config.IsFeatureEnabled("Tablet") then return end

		if isOpen then
			CloseUI()
			return
		end

		OpenFrame("openTablet")
	end

	local function TogglePos(payload)
		LogDbg("TogglePos", "m-phone")
		if Config.IsFeatureEnabled and not Config.IsFeatureEnabled("POS") then return end

		if isOpen then
			CloseUI()
			return
		end

		OpenFrame("openPos", payload)
	end

	local function ToggleDesktop(payload)
		LogDbg("ToggleDesktop", "m-phone")
		if Config.IsFeatureEnabled and not Config.IsFeatureEnabled("Desktop") then return end

		if isOpen then
			CloseUI()
			return
		end

		OpenFrame("openDesktop", payload)
	end

	-- =========================
	-- WebUI init (Main + HUD)
	-- =========================

	LogDbg("client.lua loaded, creating WebUI -> " .. UI_URL, "m-phone")

	local ScreenUI = WebUI("M_PHONE", UI_URL)
	UI = SpatialWebUI.CreateRouter(ScreenUI, {
		url = UI_URL,
		isOpen = function() return isOpen end,
		log = function(message, payload)
			LogInfo(message, "m-phone:spatial", payload)
		end,
		onSpatialStateChanged = function(active, definition)
			if not HUD then return end
			local spatial = type(definition) == "table" and type(definition.spatial) == "table" and definition.spatial or {}
			HUD:SendEvent("desktop:spatialHint", {
				visible = active == true,
				mode = tostring(spatial.mode or "desktop"),
			})
		end,
	})
	LogDbg("Main WebUI created", "m-phone")
	PhoneSDK.BindUI(UI)
	WidgetSDK.BindUI(UI)
	if CreatorLink and CreatorLink.BindUI then CreatorLink.BindUI(UI) end

	-- Register ui typing handler AFTER UI init
	UI:RegisterEventHandler("ui:typing", function(payload, cb)
		uiTyping = (type(payload) == "table" and payload.active == true) == true
		if cb then cb(true) end
	end)

	SetVisible(false)

	-- HUD WebUI (always on, no input)
	HUD = WebUI("M_PHONE_HUD", UI_URL .. "?hud=1")
	HUD:SetInputMode(0)
	HUD:SendEvent("setVisible", true)
	HUD:SendEvent("hud:mode", { enabled = true })
	HUD:SendEvent("desktop:spatialHint", { visible = false })
	LogDbg("HUD WebUI created", "m-phone")

	-- =========================
	-- React -> Lua handlers (Main UI)
	-- =========================
	local function ResolveWebUIArgs(payload, cb)
		if type(payload) == "function" and cb == nil then
			return {}, payload
		end
		return type(payload) == "table" and payload or {}, cb
	end

	local function ReplyWebUI(cb, value, eventName)
		if type(cb) ~= "function" then
			LogWarn("WebUI callback missing", "m-phone", {
				event = eventName,
				callbackType = type(cb),
			})
			return false
		end

		local ok, err = pcall(cb, value)
		if not ok then
			LogErr("WebUI callback failed", "m-phone", {
				event = eventName,
				error = tostring(err),
			})
		end
		return ok
	end

	local dataPending = {}
	local dataRequestSequence = 0

	RegisterClientEvent("m-phone:getData:result", function(payload)
		payload = type(payload) == "table" and payload or {}
		local requestId = tostring(payload.requestId or "")
		local pending = dataPending[requestId]
		if not pending then return end
		dataPending[requestId] = nil
		if payload.ok ~= true then
			LogWarn("getData failed", "m-phone", { key = pending.key, error = payload.error })
		end
		ReplyWebUI(pending.cb, payload.ok == true and payload.data or {}, "getData")
	end)

	UI:RegisterEventHandler("getData", function(payload, cb)
		payload, cb = ResolveWebUIArgs(payload, cb)
		dataRequestSequence = dataRequestSequence + 1
		local requestId = string.format("data_%d_%d", os.time(), dataRequestSequence)
		dataPending[requestId] = { cb = cb, key = tostring(payload.key or "") }
		TriggerServerEvent("m-phone:getData", { requestId = requestId, key = payload.key })
		if Timer and type(Timer.SetTimeout) == "function" then
			Timer.SetTimeout(function()
				local pending = dataPending[requestId]
				if not pending then return end
				dataPending[requestId] = nil
				LogWarn("getData timed out", "m-phone", { key = pending.key })
				ReplyWebUI(pending.cb, {}, "getData")
			end, tonumber(Config and Config.SDK and Config.SDK.RequestTimeoutMs) or 10000)
		end
	end)

	local function HandleSettingsUpdate(payload, cb)
		payload, cb = ResolveWebUIArgs(payload, cb)
		TriggerServerEvent("helix:settings:update", payload)
		ReplyWebUI(cb, true, "helix:settings:update")
	end

	-- legacy / internal name
	UI:RegisterEventHandler("settings:update", HandleSettingsUpdate)

	-- WebUI calls this (current SetupWizard uses hEvent('helix:settings:update', ...))
	UI:RegisterEventHandler("helix:settings:update", HandleSettingsUpdate)

	UI:RegisterEventHandler("settings:factoryReset", function(payload, cb)
		payload, cb = ResolveWebUIArgs(payload, cb)
		TriggerServerEvent("helix:settings:factoryReset", payload or {})
		ReplyWebUI(cb, true, "settings:factoryReset")
	end)

	-- optional alias якщо у Web назва інша
	UI:RegisterEventHandler("settings:resetFactory", function(payload, cb)
		payload, cb = ResolveWebUIArgs(payload, cb)
		local pc = ResolvePlayerController()
		if not pc then
			print("[m-phone][settings][error] resetFactory: PlayerController not resolved")
			ReplyWebUI(cb, false, "settings:resetFactory")
			return
		end

		TriggerServerEvent("helix:settings:factoryReset", payload or {})
		ReplyWebUI(cb, true, "settings:resetFactory")
	end)


	UI:RegisterEventHandler("setVisible", function(visible)
		LogDbg("UI event: setVisible", "m-phone", { visible = visible })
		if visible == true then SetVisible(true) else CloseUI() end
	end)

	UI:RegisterEventHandler("hideUI", function()
		LogDbg("UI event: hideUI", "m-phone")
		CloseUI()
	end)

	UI:RegisterEventHandler("jobcentre:setWaypoint", function(payload, cb)
		payload, cb = ResolveWebUIArgs(payload, cb)
		local coordinates = type(payload.coordinates) == "table" and payload.coordinates or nil
		if not coordinates then
			ReplyWebUI(cb, { ok = false, error = "invalid_coordinates" }, "jobcentre:setWaypoint")
			return
		end

		local ok = false
		if exports then
			local providerOk, provider = pcall(function() return exports["m-desktop"] end)
			if providerOk and provider then
				local methodOk, method = pcall(function() return provider.SetNavigationWaypoint end)
				if methodOk and type(method) == "function" then
					local callOk, result = pcall(method, provider, coordinates)
					ok = callOk and result == true
				end
			end
		end

		ReplyWebUI(cb, {
			ok = ok == true,
			error = ok and nil or "navigation_unavailable",
		}, "jobcentre:setWaypoint")
	end)

	UI:RegisterEventHandler("log", function(data, cb)
		if type(data) ~= "table" then
			Notify("warn", "log: invalid payload", "webui")
			if cb then cb(true) end
			return
		end

		local level = tostring(data.level or "info")
		local msg = tostring(data.message or "")
		local payload = data.data
		local ts = tostring(data.timestamp or "")

		if level == "error" or level == "warn" then
			Notify(level, msg, "webui", { timestamp = ts, data = payload })
		elseif level == "success" then
			Notify("success", msg, "webui")
		end

		if cb then cb(true) end
	end)

	-- =========================
	-- React -> Lua handlers (HUD)
	-- =========================

	HUD:RegisterEventHandler("hud:openPhone", function(payload, cb)
		-- payload може містити chatId
		TogglePhone()

		if type(payload) == "table" and UI then
			local appId = tostring(payload.appId or "")
			if appId == "calls" then
				UI:SendEvent("phone:openCalls", {})
			elseif payload.chatId ~= nil then
				local chatId = tostring(payload.chatId or "")
				if chatId ~= "" then
					UI:SendEvent("phone:openChat", { chatId = chatId })
				end
			end
		end

		if cb then cb(true) end
	end)

	-- =========================
	-- Unified notify + chat (exports)
	-- =========================

	local function NotifyPhone(payload)
		if type(payload) ~= "table" then return false end
		SendToUIs("notify:phone", payload)
		return true
	end
	if CreatorLink and CreatorLink.SetNotifier then CreatorLink.SetNotifier(NotifyPhone) end

	local function PushChatSystemMessage(chatId, chatName, text, prio, ttlMs, appId)
		chatId = tostring(chatId or "")
		chatName = tostring(chatName or "Message")
		text = tostring(text or "")
		prio = tostring(prio or "normal")
		ttlMs = tonumber(ttlMs or 3200) or 3200
		appId = tostring(appId or "chat")

		-- 1) push into chat UI (main only)
		SendToUI(UI, "chat:systemMessage", {
			chatId = chatId,
			chatName = chatName,
			text = text,
			priority = prio,
			createdAt = math.floor(os.time() * 1000),
		})

		-- 2) notify (HUD + Main)
		NotifyPhone({
			kind = "chat",
			appId = appId,
			chatId = chatId,
			title = chatName,
			text = text,
			ttlMs = ttlMs,
			priority = prio,
		})

		return true
	end

	-- =========================
	-- Chat API bridge (WebUI <-> Client <-> Server)
	-- =========================

	local chatPending = {}
	local chatReqSeq = 0

	local function NextChatReqId()
		chatReqSeq = chatReqSeq + 1
		return tostring(os.time()) .. "-chat-" .. tostring(chatReqSeq)
	end

	RegisterClientEvent("m-phone:chatResult", function(payload)
		local requestId = tostring(payload and payload.requestId or "")
		if requestId == "" then return end

		local pend = chatPending[requestId]
		if not pend then return end

		chatPending[requestId] = nil
		if pend.cb then
			pend.cb(payload)
		end
	end)

	RegisterClientEvent("m-phone:communicationsResult", function(payload)
		local requestId = tostring(payload and payload.requestId or "")
		if requestId == "" then return end
		local pending = chatPending[requestId]
		if not pending then return end
		chatPending[requestId] = nil
		if pending.cb then pending.cb(payload) end
	end)

	local function RegisterCommunicationHandler(uiEvent, serverEvent, validate)
		UI:RegisterEventHandler(uiEvent, function(data, cb)
			data = type(data) == "table" and data or {}
			if validate then
				local ok, err = validate(data)
				if not ok then
					if cb then cb({ ok = false, error = err }) end
					return
				end
			end
			local requestId = NextChatReqId()
			chatPending[requestId] = { cb = cb, at = os.time() }
			data.requestId = requestId
			TriggerServerEvent(serverEvent, data)
		end)
	end

	RegisterCommunicationHandler("communications:getProfile", "m-phone:communicationsGetProfile")
	RegisterCommunicationHandler("contacts:list", "m-phone:contactsList")
	RegisterCommunicationHandler("contacts:save", "m-phone:contactsSave", function(data)
		return tostring(data.name or "") ~= "" and tostring(data.phoneNumber or "") ~= "", "invalid_contact"
	end)
	RegisterCommunicationHandler("contacts:delete", "m-phone:contactsDelete", function(data)
		return tostring(data.contactId or "") ~= "", "invalid_contact"
	end)
	RegisterCommunicationHandler("contacts:setFlags", "m-phone:contactsSetFlags", function(data)
		return tostring(data.phoneNumber or "") ~= "", "invalid_contact"
	end)
	RegisterCommunicationHandler("sms:send", "m-phone:smsSend", function(data)
		return tostring(data.phoneNumber or "") ~= "" and (tostring(data.text or "") ~= "" or tostring(data.photoId or "") ~= ""), "invalid_sms"
	end)
	RegisterCommunicationHandler("calls:list", "m-phone:callsList")
	RegisterCommunicationHandler("calls:start", "m-phone:callStart", function(data)
		return tostring(data.phoneNumber or "") ~= "", "invalid_phone_number"
	end)
	RegisterCommunicationHandler("calls:action", "m-phone:callAction", function(data)
		return tostring(data.callId or "") ~= "" and tostring(data.action or "") ~= "", "invalid_call_action"
	end)

	UI:RegisterEventHandler("chat:listConversations", function(data, cb)
		local requestId = NextChatReqId()
		chatPending[requestId] = { cb = cb, at = os.time() }

		local limit = tonumber(type(data) == "table" and data.limit) or 50
		local offset = tonumber(type(data) == "table" and data.offset) or 0

		TriggerServerEvent("m-phone:chatListConversations", {
			requestId = requestId,
			limit = limit,
			offset = offset
		})
	end)

	UI:RegisterEventHandler("chat:listMessages", function(data, cb)
		local convId = tostring(type(data) == "table" and data.convId or "")
		if convId == "" then
			if cb then cb({ ok = false, error = "invalid_convId" }) end
			return
		end

		local requestId = NextChatReqId()
		chatPending[requestId] = { cb = cb, at = os.time() }

		local limit = tonumber(type(data) == "table" and data.limit) or 50
		local beforeAtMs = tonumber(type(data) == "table" and data.beforeAtMs)

		TriggerServerEvent("m-phone:chatListMessages", {
			requestId = requestId,
			convId = convId,
			limit = limit,
			beforeAtMs = beforeAtMs
		})
	end)

	UI:RegisterEventHandler("chat:markRead", function(data, cb)
		local convId = tostring(type(data) == "table" and data.convId or "")
		if convId == "" then
			if cb then cb({ ok = false, error = "invalid_convId" }) end
			return
		end

		local requestId = NextChatReqId()
		chatPending[requestId] = { cb = cb, at = os.time() }

		TriggerServerEvent("m-phone:chatMarkRead", {
			requestId = requestId,
			convId = convId
		})
	end)

	UI:RegisterEventHandler("chat:sendMessage", function(data, cb)
		local convId = tostring(type(data) == "table" and data.convId or "")
		local text = tostring(type(data) == "table" and data.text or "")

		if convId == "" then
			if cb then cb({ ok = false, error = "invalid_convId", kind = "sendMessage" }) end
			return
		end

		text = text:gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" then
			if cb then cb({ ok = false, error = "empty_text", kind = "sendMessage" }) end
			return
		end

		local requestId = NextChatReqId()
		chatPending[requestId] = { cb = cb, at = os.time() }

		TriggerServerEvent("m-phone:chatSendMessage", {
			requestId = requestId,
			convId = convId,
			text = text,
		})
	end)

	-- Server -> Client: persisted chat system message
	RegisterClientEvent("m-phone:chat:systemMessage", function(payload)
		if type(payload) ~= "table" then return end

		local chatId = tostring(payload.chatId or "")
		local chatName = tostring(payload.chatName or payload.title or "Message")
		local text = tostring(payload.text or "")
		local prio = tostring(payload.priority or "normal")
		local ttlMs = tonumber(payload.ttlMs or 3200) or 3200
		local appId = tostring(payload.appId or "chat")

		if chatId == "" or text == "" then return end
		PushChatSystemMessage(chatId, chatName, text, prio, ttlMs, appId)
	end)

	RegisterClientEvent("m-phone:chat:directMessage", function(payload)
		if type(payload) ~= "table" then return end
		local chatId = tostring(payload.chatId or "")
		local chatName = tostring(payload.chatName or payload.phoneNumber or "Message")
		local text = tostring(payload.text or "")
		if chatId == "" or text == "" then return end

		SendToUI(UI, "chat:directMessage", payload)
		NotifyPhone({
			kind = "chat",
			appId = "chat",
			chatId = chatId,
			title = chatName,
			text = text,
			ttlMs = 4200,
			priority = "normal",
		})
	end)

	RegisterClientEvent("m-phone:sms:status", function(payload)
		if type(payload) ~= "table" then return end
		SendToUI(UI, "sms:status", payload)
	end)

	RegisterClientEvent("m-phone:call:incoming", function(payload)
		if type(payload) ~= "table" then return end
		SendToUI(UI, "call:incoming", payload)
		NotifyPhone({ kind = "call", appId = "calls", title = tostring(payload.displayName or payload.phoneNumber or "Incoming call"), text = "Incoming call", ttlMs = 30000, priority = "high" })
	end)

	local activeVoiceCallId = nil
	local lastVoiceTalking = false

	RegisterClientEvent("m-phone:call:state", function(payload)
		if type(payload) ~= "table" then return end
		if tostring(payload.status or "") == "connected" and payload.voiceConnected == true then
			activeVoiceCallId = tostring(payload.callId or "")
		elseif tostring(payload.callId or "") == activeVoiceCallId and tostring(payload.status or "") ~= "connected" then
			activeVoiceCallId = nil
			lastVoiceTalking = false
		end
		SendToUI(UI, "call:state", payload)
	end)

	RegisterClientEvent("m-phone:call:voiceActivity", function(payload)
		if type(payload) ~= "table" then return end
		SendToUI(UI, "call:voiceActivity", payload)
	end)

	if Timer and type(Timer.SetInterval) == "function" then
		Timer.SetInterval(function()
			if not activeVoiceCallId then return end
			local talking = false
			if HPlayer and type(HPlayer.IsTalking) == "function" then
				local ok, result = pcall(HPlayer.IsTalking, HPlayer)
				talking = ok and result == true
			end
			if talking == lastVoiceTalking then return end
			lastVoiceTalking = talking
			SendToUI(UI, "call:voiceActivity", { callId = activeVoiceCallId, participant = "self", talking = talking })
			TriggerServerEvent("m-phone:callVoiceActivity", { callId = activeVoiceCallId, talking = talking })
		end, 250)
	end


	

	-- =========================
	-- Export CLIENT CORE to modules
	-- =========================

	_G.MPhoneClient = {
		UI = UI,
		HUD = HUD,

		LogInfo = LogInfo,
		LogWarn = LogWarn,
		LogErr = LogErr,
		LogDbg = LogDbg,
		LogOk = LogOk,

		SendToUI = SendToUI,
		SendToUIs = SendToUIs,

		SetVisible = SetVisible,
		OpenFrame = OpenFrame,
		CloseUI = CloseUI,

		TogglePhone = TogglePhone,
		ToggleTablet = ToggleTablet,
		TogglePos = TogglePos,
		ToggleDesktop = ToggleDesktop,
		ActivateSpatialDesktop = function(definition)
			if not UI or not UI.ActivateSpatial then return false, "ui_unavailable" end
			return UI:ActivateSpatial(definition)
		end,
		ActivateNativeSpatial = function(definition)
			if not UI or not UI.ActivateNativeSpatial then return false, "ui_unavailable" end
			return UI:ActivateNativeSpatial(definition)
		end,

		PushInitialData = PushInitialData,
		IsOpen = function() return isOpen end,

		NotifyPhone = NotifyPhone,
		PushChatSystemMessage = PushChatSystemMessage,
	}

	exports("m-phone", "RegisterClientUIHandler", function(eventName, handler)
		if not UI or type(UI.RegisterEventHandler) ~= "function" then
			return false, "ui_unavailable"
		end
		if type(eventName) ~= "string" or eventName == "" or type(handler) ~= "function" then
			return false, "invalid_handler"
		end
		UI:RegisterEventHandler(eventName, handler)
		return true
	end)

	exports("m-phone", "SendClientUIEvent", function(eventName, payload)
		if not UI or type(UI.SendEvent) ~= "function" then
			return false, "ui_unavailable"
		end
		UI:SendEvent(eventName, payload)
		return true
	end)

	exports("m-phone", "GetDesktopRuntimeConfig", function()
		return {
			ActiveMap = Config and Config.ActiveMap or "TEST_MAP",
			RendererUrl = UI_URL,
			Features = (Config and Config.Features) or {},
			Desktop = (Config and Config.Desktop) or {},
			Business = (Config and Config.Business) or {},
			Jobs = (Config and Config.Jobs) or {},
			CitizenServices = (Config and Config.CitizenServices) or {},
			ShopLocations = (Config and Config.ShopLocations) or {},
			ATMs = (Config and Config.ATMs) or {},
			MPhoneMarker = Config and Config.MPhoneMarker or nil,
			DoorMarker = Config and Config.DoorMarker or nil,
		}
	end)

	exports("m-phone", "FilterDesktopAllowedApps", function(apps)
		if Config and type(Config.FilterAllowedApps) == "function" then
			return Config.FilterAllowedApps(apps)
		end
		return type(apps) == "table" and apps or {}
	end)

	exports("m-phone", "IsClientUIOpen", function()
		return isOpen == true
	end)

	exports("m-phone", "OpenClientFrame", function(eventName, payload)
		eventName = tostring(eventName or "")
		if eventName == "" then return false, "invalid_frame_event" end
		OpenFrame(eventName, payload)
		return true
	end)

	exports("m-phone", "CloseClientUI", function()
		CloseUI()
		return true
	end)

	exports("m-phone", "ToggleClientFrame", function(eventName, payload)
		eventName = tostring(eventName or "")
		if eventName == "" then return false, "invalid_frame_event" end
		if isOpen then
			CloseUI()
		else
			OpenFrame(eventName, payload)
		end
		return true
	end)

	exports("m-phone", "PushClientInitialData", function(payload)
		PushInitialData(payload)
		return true
	end)

	exports("m-phone", "DesktopOpenFrame", function(eventName, payload)
		OpenFrame(eventName, payload)
		return true
	end)

	exports("m-phone", "DesktopTogglePos", function(payload)
		TogglePos(payload)
		return true
	end)

	exports("m-phone", "DesktopToggle", function(payload)
		ToggleDesktop(payload)
		return true
	end)

	exports("m-phone", "DesktopPushInitialData", function(payload)
		PushInitialData(payload)
		return true
	end)

	exports("m-phone", "DesktopAttachSpatialUI", function(spatial, definition)
		if not UI or type(UI.AttachSpatialUI) ~= "function" then
			return false, "ui_bridge_unavailable"
		end
		return UI:AttachSpatialUI(spatial, definition)
	end)

	exports("m-phone", "DesktopDetachSpatialUI", function(spatial)
		if not UI or type(UI.DetachSpatialUI) ~= "function" then
			return false, "ui_bridge_unavailable"
		end
		return UI:DetachSpatialUI(spatial)
	end)

	exports("m-phone", "DesktopSetNativeSpatialState", function(active, definition)
		if not UI or type(UI.SetNativeSpatialState) ~= "function" then
			return false, "ui_bridge_unavailable"
		end
		return UI:SetNativeSpatialState(active == true, definition)
	end)

	exports("m-phone", "DesktopActivateSpatial", function(definition)
		if not UI or type(UI.ActivateSpatial) ~= "function" then
			return false, "ui_unavailable"
		end
		return UI:ActivateSpatial(definition)
	end)

	exports("m-phone", "DesktopActivateNativeSpatial", function(definition)
		if not UI or type(UI.ActivateNativeSpatial) ~= "function" then
			return false, "ui_unavailable"
		end
		return UI:ActivateNativeSpatial(definition)
	end)

	exports("m-phone", "DesktopDeactivateSpatial", function()
		if not UI or type(UI.DeactivateSpatial) ~= "function" then
			return false, "ui_unavailable"
		end
		return UI:DeactivateSpatial()
	end)

	exports("m-phone", "DesktopRefreshMapMarkers", function()
		if not exports then return false, "exports_unavailable" end
		local providerOk, provider = pcall(function() return exports["m-desktop"] end)
		if not providerOk or not provider then return false, "m_desktop_unavailable" end
		local methodOk, method = pcall(function() return provider.RefreshMapMarkers end)
		if not methodOk or type(method) ~= "function" then return false, "map_markers_unavailable" end
		local ok, result = pcall(method, provider)
		if not ok then return false, tostring(result) end
		return result ~= false
	end)

	exports("m-phone", "UpdateTruckerRouteMarker", function(route)
		if not exports then return false, "exports_unavailable" end
		local providerOk, provider = pcall(function() return exports["m-desktop"] end)
		if not providerOk or not provider then return false, "m_desktop_unavailable" end
		local methodOk, method = pcall(function() return provider.UpdateTruckerRouteMarker end)
		if not methodOk or type(method) ~= "function" then return false, "route_markers_unavailable" end
		local ok, result = pcall(method, provider, route)
		if not ok then return false, tostring(result) end
		return result ~= false
	end)

	exports("m-phone", "SetTruckerVehicleMarker", function(actor)
		if not exports then return false, "exports_unavailable" end
		local providerOk, provider = pcall(function() return exports["m-desktop"] end)
		if not providerOk or not provider then return false, "m_desktop_unavailable" end
		local methodOk, method = pcall(function() return provider.SetTruckerVehicleMarker end)
		if not methodOk or type(method) ~= "function" then return false, "vehicle_markers_unavailable" end
		local ok, result = pcall(method, provider, actor)
		if not ok then return false, tostring(result) end
		return result ~= false
	end)

	-- =========================
	-- Modules
	-- =========================

	local function LoadFeatureModule(feature, moduleName)
		if not FeatureEnabled(feature) then
			LogInfo("feature disabled: " .. tostring(feature), "m-phone")
			return false
		end
		local ok, result = pcall(require, moduleName)
		if not ok then
			LogErr("feature module failed: " .. tostring(moduleName) .. " | " .. tostring(result), "m-phone")
			return false
		end
		return true
	end

	LoadFeatureModule("ParkingMeter", "WorldSystems.ParkingMeter.client")
	LoadFeatureModule("Bank", "PhoneApps.Bank.bank_client")
	LoadFeatureModule("POS", "PosApps.Kiosk.kiosk_client")
	LoadFeatureModule("Rewards", "Services.Rewards.rewards_client")
	LoadFeatureModule("Courier", "PhoneApps.Courier.client")
	LoadFeatureModule("Garage", "PhoneApps.Garage.client")
	LoadFeatureModule("Parking", "PhoneApps.Parking.client")
	LoadFeatureModule("Camera", "PhoneApps.Camera.camera_client")

	LogInfo("CLIENT CORE loaded (modules required)", "m-phone")

	-- =========================
	-- Keybinds
	-- =========================

	local function IsUiOpen()
		if (_G.MPhoneClient and _G.MPhoneClient.IsOpen and _G.MPhoneClient.IsOpen()) == true then
			return true
		end
		if UI and type(UI.IsSpatialWidget) == "function" then
			local ok, active = pcall(function() return UI:IsSpatialWidget() end)
			if ok and active == true then return true end
		end
		return false
	end

	-- Найнадійніше: поки UI відкритий, не даємо хоткеям M/T/P/Up спрацьовувати взагалі
	Input.BindKey("Up", function()
		if IsUiOpen() then return end
		if HPlayer and HPlayer.GetInputMode and HPlayer:GetInputMode() == 1 then return end
		TogglePhone()
	end, "Pressed")

	Input.BindKey("Escape", function()
		if IsUiOpen() then
			CloseUI()
		end
	end, "Pressed")

	Input.BindKey("BackSpace", function()
		if IsUiOpen() then
			CloseUI()
		end
	end, "Pressed")

	if Config and Config.Debug == true then
		Input.BindKey("F3", function()
			TriggerServerEvent("m-phone:debug:whoami")
		end, "Pressed")
	end

	-- =========================
	-- Shutdown
	-- =========================

	function onShutdown()
		LogDbg("onShutdown", "m-phone")
		EndPhoneUse(true)
		StopAnim()
		if _G.MPhoneCamera and _G.MPhoneCamera.Close then
			pcall(_G.MPhoneCamera.Close)
		end

		if UI then
			UI:Destroy()
			UI = nil
		end

		if HUD then
			HUD:Destroy()
			HUD = nil
		end
	end

	print("[m-phone][client][ready] resource started successfully")
