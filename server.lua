-- m-phone/server.lua
-- CORE + LOADER
-- simplified / stable trucker bridge

local Shared = require("server_shared")
local Helpers = require("server_helpers")
local PhoneSDK = require("AppSDK.server")
local WidgetSDK = require("WidgetSDK.server")

local function FeatureEnabled(name)
	return not Config or not Config.IsFeatureEnabled or Config.IsFeatureEnabled(name)
end

local QB = nil
pcall(function() QB = exports["qb-core"] end)

print("[m-phone][server] LOADED server.lua")

local function AnyFeatureEnabled(features)
	for _, featureName in ipairs(type(features) == "table" and features or {}) do
		if FeatureEnabled(featureName) then return true end
	end
	return false
end

local function ConfiguredBankProvider()
	local provider = tostring(Config and Config.Use and Config.Use.Bank or "qb"):lower()
	if provider == "m" or provider == "m-bank" or provider == "m-banking" then return "mbank" end
	if provider == "qb-core" or provider == "qbcore" then return "qb" end
	return provider
end

local function LogDependencyStatus()
	local dependencies = Config and Config.Dependencies or {}
	local inventoryImages = Helpers.ResolveInventoryImages()
	local inventoryProvider = tostring(inventoryImages.provider or "none")
	for _, packageName in ipairs(dependencies.Required or {}) do
		print(string.format(
			"[m-phone][dependency][required] package=%s",
			tostring(packageName)
		))
	end
	local optionalNames = {}
	for packageName in pairs(dependencies.Optional or {}) do optionalNames[#optionalNames + 1] = packageName end
	table.sort(optionalNames)
	for _, packageName in ipairs(optionalNames) do
		local features = dependencies.Optional[packageName]
		local enabled = AnyFeatureEnabled(features)
		if packageName == "m-banking" then
			enabled = enabled and ConfiguredBankProvider() == "mbank"
		elseif packageName == "m-attachments" then
			enabled = enabled and Config and Config.PhoneUse and Config.PhoneUse.Attachment and Config.PhoneUse.Attachment.enabled == true
		end
		local status = enabled and "configured" or "inactive"
		print(string.format(
			"[m-phone][dependency][%s] optional package=%s features=%s",
			status,
			tostring(packageName),
			table.concat(features or {}, ",")
		))
	end
	local bankProvider = ConfiguredBankProvider()
	if bankProvider ~= "qb" and bankProvider ~= "mbank" then
		print(string.format("[m-phone][dependency][error] unsupported-bank-provider=%s expected=qb,mbank", bankProvider))
	end
	if inventoryProvider == "none" then
		print("[m-phone][dependency][inactive] configured-inventory-provider=none purpose=item-images,business-adapter")
	else
		print(string.format(
			"[m-phone][dependency][configured] inventory-provider=%s resolution=%s purpose=item-images,business-adapter",
			inventoryProvider,
			tostring(inventoryImages.resolution or "explicit")
		))
	end
end

LogDependencyStatus()

local DB = require("db")
local Communications

local okInit, errInit = pcall(function()
	DB.Init()
end)

if not okInit then
	print("[m-phone][server][error] DB.Init failed: " .. tostring(errInit))
end

if FeatureEnabled("CreatorLink") then
	local creatorLinkOk, creatorLinkError = pcall(require, "PhoneApps.CreatorLink.server")
	if not creatorLinkOk then print("[m-phone][server][error] CreatorLink load failed: " .. tostring(creatorLinkError)) end
end

local function NowMs()
	return Shared.NowMs()
end

local function sTable(t, depth)
	return Shared.TableToString(t, depth)
end

local function SLog(level, msg, extra)
	print(string.format(
		"[m-phone][server][%s] %s%s",
		tostring(level),
		tostring(msg),
		extra ~= nil and (" " .. sTable(extra)) or ""
	))
end

local function SInfo(msg, extra) SLog("info", msg, extra) end
local function SWarn(msg, extra) SLog("warn", msg, extra) end
local function SErr(msg, extra)  SLog("error", msg, extra) end

local function ResolveControllerAndPayload(a, b)
	return Shared.ResolveControllerAndPayload(a, b)
end

local function GetPlayerId(src)
	if not src then
		return ""
	end

	if src.GetLyraPlayerState then
		local okPS, ps = pcall(function()
			return src:GetLyraPlayerState()
		end)

		if okPS and ps and ps.GetHelixUserId then
			local okId, uid = pcall(function()
				return ps:GetHelixUserId()
			end)

			if okId and uid then
				uid = tostring(uid)

				if uid ~= "" then
					return "helix:" .. uid
				end
			end
		end
	end

	SWarn("GetPlayerId: HELIX USER ID NOT FOUND", {
		source = tostring(src),
		sourceType = type(src),
	})

	return ""
end

_G.MPhone = _G.MPhone or {}
_G.MPhone.DB = DB
_G.MPhone.QB = QB
_G.MPhone.SInfo = SInfo
_G.MPhone.SWarn = SWarn
_G.MPhone.SErr = SErr
_G.MPhone.GetPlayerId = GetPlayerId
local Banking = require("Integrations.Banking.server")
Banking.InstallLegacyDbBridge(DB)
_G.MPhone.Banking = Banking
SInfo("Banking integration selected", { provider = Banking.Provider() })
local Trucker = require("Integrations.Trucker.server")
_G.MPhone.Trucker = Trucker
local Courier = require("Integrations.Courier.server")
_G.MPhone.Courier = Courier
local Business = require("Integrations.Business.server")
_G.MPhone.Business = Business
if Config.IsFeatureEnabled("POS") or Config.IsFeatureEnabled("ShopManager") or Config.IsFeatureEnabled("FurnitureStore") then
	local businessConfigResult, businessConfigError = Business.Configure()
	if type(businessConfigResult) ~= "table" or businessConfigResult.ok ~= true then
		SWarn("Business configuration failed", { error = businessConfigError or (businessConfigResult and businessConfigResult.error) })
	else
		local shopCount = 0
		for _ in pairs(businessConfigResult.data and businessConfigResult.data.shops or {}) do shopCount = shopCount + 1 end
		SInfo("Business configuration synchronized", { shops = shopCount })
	end
end
local Jobs = require("Integrations.Jobs.server")
_G.MPhone.Jobs = Jobs
if Config.IsFeatureEnabled("JobCentre") then
	if Jobs.IsReady() then SInfo("Jobs integration ready") else SWarn("Jobs integration unavailable") end
end

exports("m-phone", "DocumentsGet", function(documentId)
	return DB.Documents.Get(documentId)
end)

exports("m-phone", "DocumentsGetActive", function(holderId, documentType)
	return DB.Documents.GetActive(holderId, documentType)
end)

exports("m-phone", "DocumentsGetByRequestId", function(requestId)
	return DB.Documents.GetByRequestId(requestId)
end)

exports("m-phone", "DocumentsCreatePending", function(document)
	return DB.Documents.CreatePending(document)
end)

exports("m-phone", "DocumentsSetStatus", function(documentId, status)
	return DB.Documents.SetStatus(documentId, status)
end)

exports("m-phone", "DocumentsCancel", function(documentId)
	return DB.Documents.Cancel(documentId)
end)

exports("m-phone", "GetPlayerId", function(controller)
	return GetPlayerId(controller)
end)

exports("m-phone", "ListPlayerPhotos", function(playerId, limit, offset)
	if not DB or not DB.Photos or type(DB.Photos.List) ~= "function" then return {} end
	return DB.Photos.List(tostring(playerId or ""), tonumber(limit) or 100, tonumber(offset) or 0)
end)

exports("m-phone", "GetPlayerPhoto", function(playerId, photoId)
	if not DB or not DB.Photos or type(DB.Photos.Get) ~= "function" then return nil end
	return DB.Photos.Get(tostring(playerId or ""), tostring(photoId or ""))
end)

exports("m-phone", "TruckerSupplyMarkDelivered", function(orderId)
	return Business.MarkSupplyDeliveredByTruckerOrder(orderId)
end)

exports("m-phone", "TruckerSupplyCancel", function(orderId, status, reason, meta)
	return Business.CancelSupplyByTruckerOrder(orderId, status, reason, meta)
end)

exports("m-phone", "TruckerSupplySetStatus", function(orderId, status)
	return Business.SetSupplyStatusByTruckerOrder(orderId, status)
end)

exports("m-phone", "GetPlayerLanguage", function(controller, fallback)
	local defaultLanguage = tostring(fallback or "en")
	local pid = GetPlayerId(controller)
	if pid == "" then
		return defaultLanguage
	end

	local settings = DB.GetSettings(pid)
	local language = settings and tostring(settings.language or "") or ""
	if language == "" then
		return defaultLanguage
	end
	return language
end)

exports("m-phone", "SetPlayerLanguage", function(controller, language)
	local pid = GetPlayerId(controller)
	if pid == "" then
		return false
	end
	return DB.UpsertSettings(pid, {
		language = tostring(language or "en"),
	}) == true
end)

exports("m-phone", "GetDesktopRuntimeConfig", function()
	return {
		ActiveMap = Config and Config.ActiveMap or "TEST_MAP",
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

exports("m-phone", "BankCredit", function(controller, amountPence, reference, extra)
	extra = type(extra) == "table" and extra or {}
	extra.transactionType = extra.transactionType or "admin_credit"
	return Banking.Credit(controller, math.floor(tonumber(amountPence) or 0), reference or "External bank credit", extra)
end)

exports("m-phone", "BankGetBalance", function(controller)
	return Banking.GetBalance(controller)
end)

exports("m-phone", "BankDebit", function(controller, amountPence, reference, extra)
	extra = type(extra) == "table" and extra or {}
	extra.transactionType = extra.transactionType or "external_purchase"
	return Banking.Debit(controller, math.floor(tonumber(amountPence) or 0), reference or "External bank purchase", extra)
end)

exports("m-phone", "BankClear", function(controller, reference, extra)
	extra = type(extra) == "table" and extra or {}
	extra.transactionType = extra.transactionType or "admin_debit"
	return Banking.Clear(controller, reference or "External bank clear", extra)
end)

exports("m-phone", "BankProvider", function()
	return Banking.Provider()
end)

exports("m-phone", "BankGetAccountByPlayerId", function(playerId)
	return Banking.GetAccountByPlayerId(tostring(playerId or ""))
end)

exports("m-phone", "BankCreditByPlayerId", function(playerId, amountPence, reference, extra)
	extra = type(extra) == "table" and extra or {}
	extra.transactionType = extra.transactionType or "external_credit"
	return Banking.CreditByPlayerId(
		tostring(playerId or ""),
		math.floor(tonumber(amountPence) or 0),
		reference or "External bank credit",
		extra
	)
end)

exports("m-phone", "BankDebitByPlayerId", function(playerId, amountPence, reference, extra)
	extra = type(extra) == "table" and extra or {}
	extra.transactionType = extra.transactionType or "external_purchase"
	return Banking.DebitByPlayerId(
		tostring(playerId or ""),
		math.floor(tonumber(amountPence) or 0),
		reference or "External bank purchase",
		extra
	)
end)

exports("m-phone", "BankGetAtmProfile", function(controller, definition)
	return Banking.GetAtmProfile(controller, definition)
end)

exports("m-phone", "BankTransactAtm", function(controller, definition, data)
	return Banking.TransactAtm(controller, definition, data)
end)

exports("m-phone", "BankNotifyPlayerDebit", function(controller, debitResult, amountPence, reference, extra)
	return Banking.NotifyPlayerDebit(controller, debitResult, amountPence, reference, extra)
end)

local function GenMsgId()
	return ("sys|%s|%s"):format(tostring(NowMs()), tostring(math.random(1000, 9999)))
end

local function SendChatSystemMessage(controller, payload)
	if not controller or type(payload) ~= "table" then
		return false
	end

	local chatId = tostring(payload.chatId or "")
	local text = tostring(payload.text or "")

	if chatId == "" or text == "" then
		return false
	end

	local pid = tostring(GetPlayerId(controller) or "")
	if pid == "" then
		return false
	end

	local chatName = tostring(payload.chatName or payload.title or "Message")
	local appId = tostring(payload.appId or "chat")
	local sender = tostring(payload.sender or "system")
	local createdAt = tonumber(payload.createdAt or payload.createdAtMs) or NowMs()
	local msgId = tostring(payload.msgId or payload.id or "")

	if msgId == "" then
		msgId = GenMsgId()
	end

	if DB and DB.Chat and DB.Chat.AddIncoming then
		DB.Chat.AddIncoming(
			pid,
			chatId,
			appId,
			chatName,
			msgId,
			createdAt,
			sender,
			text,
			payload.metaJson,
			false,
			500
		)
	end

	TriggerClientEvent(controller, "m-phone:chat:systemMessage", {
		chatId = chatId,
		chatName = chatName,
		appId = appId,
		sender = sender,
		text = text,
		createdAt = createdAt,
		msgId = msgId,
		priority = payload.priority,
		ttlMs = payload.ttlMs,
	})

	return true
end

_G.MPhone.SendChatSystemMessage = SendChatSystemMessage

exports("m-phone", "SendSystemMessage", function(controller, payload)
	return SendChatSystemMessage(controller, payload)
end)

RegisterServerEvent("m-phone:chatListConversations", function(a, b)
	local controller, data = ResolveControllerAndPayload(a, b)
	local requestId = tostring(type(data) == "table" and data.requestId or "")

	if not DB or not DB.Chat then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "db_missing",
			kind = "listConversations",
			meta = { timestamp = NowMs() }
		})
		return
	end

	local pid = tostring(GetPlayerId(controller) or "")
	if pid == "" then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "player_not_found",
			kind = "listConversations",
			meta = { timestamp = NowMs() }
		})
		return
	end

	local limit = tonumber(type(data) == "table" and data.limit) or 50
	local offset = tonumber(type(data) == "table" and data.offset) or 0
	local convs = DB.Chat.ListConversations(pid, limit, offset) or {}

	TriggerClientEvent(controller, "m-phone:chatResult", {
		requestId = requestId,
		ok = true,
		kind = "listConversations",
		data = convs,
		meta = { timestamp = NowMs() }
	})
end)

local function GenUserMsgId()
	return ("usr|%s|%s"):format(tostring(NowMs()), tostring(math.random(1000, 9999)))
end

RegisterServerEvent("m-phone:chatSendMessage", function(a, b)
	local controller, data = ResolveControllerAndPayload(a, b)

	local requestId = tostring(type(data) == "table" and data.requestId or "")
	local convId = tostring(type(data) == "table" and data.convId or "")
	local text = tostring(type(data) == "table" and data.text or "")

	if convId == "" then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "invalid_convId",
			kind = "sendMessage",
			meta = { timestamp = NowMs() }
		})
		return
	end

	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "empty_text",
			kind = "sendMessage",
			meta = { timestamp = NowMs() }
		})
		return
	end

	if not DB or not DB.Chat or not DB.Chat.AddIncoming then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "db_missing",
			kind = "sendMessage",
			meta = { timestamp = NowMs() }
		})
		return
	end

	local pid = tostring(GetPlayerId(controller) or "")
	if pid == "" then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "player_not_found",
			kind = "sendMessage",
			meta = { timestamp = NowMs() }
		})
		return
	end

	local createdAt = NowMs()
	local msgId = GenUserMsgId()

	DB.Chat.AddIncoming(
		pid,
		convId,
		"chat",
		convId,
		msgId,
		createdAt,
		"me",
		text,
		nil,
		true,
		500
	)

	TriggerClientEvent(controller, "m-phone:chatResult", {
		requestId = requestId,
		ok = true,
		kind = "sendMessage",
		data = {
			convId = convId,
			msgId = msgId,
			createdAt = createdAt,
		},
		meta = { timestamp = NowMs() }
	})
end)

RegisterServerEvent("m-phone:chatListMessages", function(a, b)
	local controller, data = ResolveControllerAndPayload(a, b)
	local requestId = tostring(type(data) == "table" and data.requestId or "")
	local convId = tostring(type(data) == "table" and data.convId or "")

	if convId == "" then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "invalid_convId",
			kind = "listMessages",
			meta = { timestamp = NowMs() }
		})
		return
	end

	if not DB or not DB.Chat then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "db_missing",
			kind = "listMessages",
			meta = { timestamp = NowMs() }
		})
		return
	end

	local pid = tostring(GetPlayerId(controller) or "")
	if pid == "" then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "player_not_found",
			kind = "listMessages",
			meta = { timestamp = NowMs() }
		})
		return
	end

	local limit = tonumber(type(data) == "table" and data.limit) or 50
	local beforeAt = tonumber(type(data) == "table" and data.beforeAtMs)
	local msgs = DB.Chat.ListMessages(pid, convId, limit, beforeAt) or {}
	if _G.MPhone and _G.MPhone.Communications and DB.Communications and tostring(convId):match("^sms:") then
		local statuses = DB.Communications.ListSmsStatuses(pid, convId)
		for _, message in ipairs(msgs) do
			local logicalId = tostring(message.msgId or ""):gsub(":out$", "")
			local receipt = statuses[logicalId]
			if receipt then
				message.deliveryStatus = receipt.status
				message.deliveredAt = receipt.deliveredAt
				message.readAt = receipt.readAt
			end
		end
	end

	TriggerClientEvent(controller, "m-phone:chatResult", {
		requestId = requestId,
		ok = true,
		kind = "listMessages",
		data = {
			convId = convId,
			messages = msgs,
		},
		meta = { timestamp = NowMs() }
	})
end)

RegisterServerEvent("m-phone:chatMarkRead", function(a, b)
	local controller, data = ResolveControllerAndPayload(a, b)
	local requestId = tostring(type(data) == "table" and data.requestId or "")
	local convId = tostring(type(data) == "table" and data.convId or "")

	if convId == "" then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "invalid_convId",
			kind = "markRead",
			meta = { timestamp = NowMs() }
		})
		return
	end

	if not DB or not DB.Chat then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "db_missing",
			kind = "markRead",
			meta = { timestamp = NowMs() }
		})
		return
	end

	local pid = tostring(GetPlayerId(controller) or "")
	if pid == "" then
		TriggerClientEvent(controller, "m-phone:chatResult", {
			requestId = requestId,
			ok = false,
			error = "player_not_found",
			kind = "markRead",
			meta = { timestamp = NowMs() }
		})
		return
	end

	DB.Chat.MarkRead(pid, convId)
	if _G.MPhone and _G.MPhone.Communications and _G.MPhone.Communications.MarkConversationRead then
		_G.MPhone.Communications.MarkConversationRead(controller, convId)
	end

	TriggerClientEvent(controller, "m-phone:chatResult", {
		requestId = requestId,
		ok = true,
		kind = "markRead",
		data = { convId = convId },
		meta = { timestamp = NowMs() }
	})
end)

RegisterServerEvent("m-phone:chat:sendSystem", function(a, b)
	local controller, payload = ResolveControllerAndPayload(a, b)
	SendChatSystemMessage(controller, payload)
end)

function onShutdown()
	print("[m-phone][server] onShutdown")
	if Communications and Communications.Shutdown then
		Communications.Shutdown()
	end

	if DB and DB.Shutdown then
		DB.Shutdown()
		print("[m-phone][DB] onShutdown")
	end
end

Communications = require("communications_server").Setup({
	DB = DB,
	GetPlayerId = GetPlayerId,
	ResolveControllerAndPayload = ResolveControllerAndPayload,
	LogInfo = SInfo,
	LogWarn = SWarn,
})

_G.MPhone.Communications = Communications

local function LoadFeatureModule(feature, moduleName)
	if not FeatureEnabled(feature) then
		SInfo("feature disabled", { feature = feature, module = moduleName })
		return false
	end
	local ok, result = pcall(require, moduleName)
	if not ok then
		SErr("feature module failed", { feature = feature, module = moduleName, error = tostring(result) })
		return false
	end
	return true
end

LoadFeatureModule("Bank", "PhoneApps.Bank.bank_server")
LoadFeatureModule("POS", "PosApps.Kiosk.kiosk_server")
LoadFeatureModule("Rewards", "Services.Rewards.rewards_server")
LoadFeatureModule("Courier", "PhoneApps.Courier.server")
LoadFeatureModule("Garage", "PhoneApps.Garage.server")
LoadFeatureModule("Parking", "PhoneApps.Parking.server")
LoadFeatureModule("Camera", "PhoneApps.Camera.camera_server")
LoadFeatureModule("ParkingMeter", "WorldSystems.ParkingMeter.server")

SInfo("CORE loaded (modules required)")

local function BuildPhoneMeta(pid)
	return Helpers.BuildPhoneMeta(pid)
end

RegisterServerEvent("helix:settings:update", function(a, b)
	local controller, payload = ResolveControllerAndPayload(a, b)

	local pid = GetPlayerId(controller)
	if pid == "" then
		return
	end

	local ok = DB.UpsertSettings(pid, payload)
	if ok ~= true then
		SErr("helix:settings:update DB write failed", {
			pid = pid,
			setupCompleted = type(payload) == "table" and payload.setupCompleted or nil,
		})
		return
	end

	TriggerClientEvent(controller, "helix:data:payload", {
		meta = BuildPhoneMeta(pid)
	})
end)

RegisterServerEvent("helix:settings:factoryReset", function(a, b)
	local controller, payload = ResolveControllerAndPayload(a, b)

	local pid = GetPlayerId(controller)
	if pid == "" then
		return
	end

	local ok = DB.ResetSettingsFactory(pid)
	if ok ~= true then
		SErr("helix:settings:factoryReset DB write failed", { pid = pid })
		TriggerClientEvent(controller, "helix:settings:factoryReset:result", { ok = false })
		return
	end

	TriggerClientEvent(controller, "helix:data:payload", {
		meta = BuildPhoneMeta(pid)
	})

	TriggerClientEvent(controller, "helix:settings:factoryReset:result", {
		ok = ok == true
	})
end)

local function PushFullPayload(controller, pid, requestData)
	return Helpers.PushFullPayload(controller, pid, requestData, {
		info = SInfo,
		warn = SWarn,
		error = SErr,
	})
end

RegisterServerEvent("helix:data:request", function(a, b)
	if Debug == true then
		print("[m-phone][server][debug] helix:data:request EVENT ENTER")
		print("[m-phone][server][debug] argA=" .. tostring(a) .. " type=" .. tostring(type(a)))
		print("[m-phone][server][debug] argB=" .. tostring(b) .. " type=" .. tostring(type(b)))
		print("[m-phone][server][debug] source=" .. tostring(source) .. " type=" .. tostring(type(source)))
	end

	local controller, data = ResolveControllerAndPayload(a, b)

	if Debug == true then print("[m-phone][server][debug] resolved controller=" .. tostring(controller) .. " type=" .. tostring(type(controller))) end

	local pid = tostring(GetPlayerId(controller) or "")

	if Debug == true then print("[m-phone][server][debug] resolved pid=" .. tostring(pid)) end

	if pid == "" then
		SErr("helix:data:request -> empty pid", {
			controller = tostring(controller),
			controllerType = type(controller),
			source = tostring(source),
			sourceType = type(source),
		})
		return
	end

	if Communications and Communications.EnsureProfile then
		local profile, profileError = Communications.EnsureProfile(controller)
		if not profile then
			SWarn("phone profile initialization failed", { pid = pid, error = profileError })
		end
	end

	PushFullPayload(controller, pid, data)
end)

RegisterServerEvent("m-phone:getData", function(a, b)
	local controller, data = ResolveControllerAndPayload(a, b)

	data = type(data) == "table" and data or {}

	local key = tostring(data.key or "")
	local requestId = tostring(data.requestId or "")
	local pid = tostring(GetPlayerId(controller) or "")

	if pid == "" then
		SErr("m-phone:getData -> empty pid", { key = key })

		TriggerClientEvent(controller, "m-phone:getData:result", {
			requestId = requestId,
			key = key,
			ok = false,
			error = "player_not_found",
			data = nil,
		})
		return
	end

	if DB and DB.Init then
		DB.Init()
	end

	local result = nil
	local ok = true
	local err = nil

	local api = Helpers.ResolveTruckerApi()
	if not FeatureEnabled("Trucker") then
		ok = false
		err = "feature_disabled"
	end

	if ok and api.ensureProfile then
		pcall(function()
			api.ensureProfile(pid)
		end)
	end

	if ok and key == "trucker.orders" then
		if api.getOrders then
			local okCall, value = pcall(function()
				return api.getOrders(pid, 50)
			end)

			if okCall then
				result = type(value) == "table" and value or {}
			else
				ok = false
				err = "trucker_orders_handler_failed"
				SWarn("m-phone:getData trucker.orders failed", {
					pid = pid,
					error = tostring(value)
				})
			end
		else
			ok = false
			err = "trucker_orders_handler_missing"
		end

	elseif ok and key == "trucker.profile" then
		if api.getProfile then
			local okCall, value = pcall(function()
				return api.getProfile(pid)
			end)

			if okCall then
				result = value
			else
				ok = false
				err = "trucker_profile_handler_failed"
				SWarn("m-phone:getData trucker.profile failed", {
					pid = pid,
					error = tostring(value)
				})
			end
		else
			ok = false
			err = "trucker_profile_handler_missing"
		end

	elseif ok and key == "trucker.activeRoutes" then
		if api.getActiveRoute then
			local okCall, value = pcall(function()
				return api.getActiveRoute(pid)
			end)

			if okCall then
				result = (type(value) == "table" and next(value) ~= nil) and { value } or {}
			else
				ok = false
				err = "trucker_active_route_handler_failed"
				SWarn("m-phone:getData trucker.activeRoutes failed", {
					pid = pid,
					error = tostring(value)
				})
			end
		else
			ok = false
			err = "trucker_active_route_handler_missing"
		end

	elseif ok then
		ok = false
		err = "unsupported_key"
	end

	if Debug == true then SInfo("m-phone:getData result", {
		key = key,
		pid = pid,
		ok = ok,
		err = err,
		count = type(result) == "table" and #result or nil,
	}) end

	TriggerClientEvent(controller, "m-phone:getData:result", {
		requestId = requestId,
		key = key,
		ok = ok,
		error = err,
		data = result,
	})
end)

RegisterServerEvent("m-phone:debug:whoami", function(a, b)
	if Debug ~= true then return end
	local src = select(1, Shared.ResolveControllerAndPayload(a, b))
	print("========== [m-phone] DEBUG whoami ==========")
	print("[m-phone] source: " .. tostring(src))
	print("[m-phone] sourceType: " .. tostring(type(src)))

	local pid = ""
	if _G.MPhone and _G.MPhone.GetPlayerId then
		pid = tostring(_G.MPhone.GetPlayerId(src) or "")
	end
	print("[m-phone] GetPlayerId() -> " .. tostring(pid))

	if pid == "" or not (_G.MPhone and _G.MPhone.DB and _G.MPhone.DB.GetBankProfile) then
		print("[m-phone][BANK] DB or pid not available")
		print("===========================================")
		return
	end

	local row = _G.MPhone.DB.GetBankProfile(pid)
	if not row then
		print("[m-phone][BANK] Account NOT FOUND for pid")
		print("===========================================")
		return
	end

	print("[m-phone][BANK] Account FOUND")
	print("[m-phone][BANK] row tostring: " .. tostring(row))

	local accountId = _G.MPhone.DB.RowGet(row, "AccountId", "accountId")
	local planId = _G.MPhone.DB.RowGet(row, "PlanId", "planId")
	local balance = _G.MPhone.DB.RowGet(row, "Balance", "balance")
	local holderName = _G.MPhone.DB.RowGet(row, "HolderName", "holderName")
	local cardNumber = _G.MPhone.DB.RowGet(row, "CardNumber", "cardNumber")

	print("[m-phone][BANK] accountId: " .. tostring(accountId))
	print("[m-phone][BANK] planId: " .. tostring(planId))
	print("[m-phone][BANK] balance: " .. tostring(balance))
	print("[m-phone][BANK] holderName: " .. tostring(holderName))

	cardNumber = tostring(cardNumber or "")
	if cardNumber ~= "" then
		print("[m-phone][BANK] cardLast4: " .. tostring(string.sub(cardNumber, -4)))
	else
		print("[m-phone][BANK] cardLast4: nil")
	end

	print("===========================================")
end)

print("[m-phone][server][ready] resource started successfully")
