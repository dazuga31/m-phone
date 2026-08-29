local Shared = require("server_shared")
local Core = _G.MPhone
if not Core then
	print("[m-phone][Camera][error] Core (_G.MPhone) not found")
	return
end

local DB = Core.DB
local cameraConfig = type(Config.Camera) == "table" and Config.Camera or {}
local storageConfig = type(cameraConfig.Storage) == "table" and cameraConfig.Storage or {}
local customStorageConfig = type(storageConfig.Custom) == "table" and storageConfig.Custom or {}
local storageSecrets = require("PhoneApps.Camera.camera_storage_server")
local recentSaves = {}
local uploadTickets = {}

local function Reply(controller, requestId, ok, errorText, data)
	TriggerClientEvent(controller, "m-phone:camera:result", {
		requestId = tostring(requestId or ""),
		ok = ok == true,
		error = errorText,
		data = data,
	})
end

local function Resolve(a, b)
	local controller, payload = Shared.ResolveControllerAndPayload(a, b)
	payload = type(payload) == "table" and payload or {}
	local requestId = tostring(payload.requestId or "")
	local playerId = tostring(Core.GetPlayerId and Core.GetPlayerId(controller) or "")
	return controller, payload, requestId, playerId
end

local function IsValidUrl(url, storageKey)
	if #url < 8 or #url > 4096 then return false end
	local storageMode = tostring(storageConfig.Mode or ""):lower()
	if storageMode == "custom" then
		local baseUrl = tostring(storageSecrets.CustomBaseUrl or ""):gsub("/+$", "")
		local expectedPrefix = baseUrl .. "/api/mphone/photos/file/"
		local photoId, deleteToken = tostring(storageKey or ""):match("^([%x-]+)%.([%x]+)$")
		return baseUrl ~= ""
			and url == expectedPrefix .. photoId
			and photoId ~= nil
			and #photoId == 36
			and deleteToken ~= nil
			and #deleteToken == 64
	end
	return url:match("^https://r2%.fivemanage%.com/") ~= nil
end

local function GetRemoteDeleteUrl(storageKey)
	local storageMode = tostring(storageConfig.Mode or ""):lower()
	if storageMode ~= "custom" then return nil end
	local photoId, deleteToken = tostring(storageKey or ""):match("^([%x-]+)%.([%x]+)$")
	if not photoId or #photoId ~= 36 or not deleteToken or #deleteToken ~= 64 then return nil end
	local baseUrl = tostring(storageSecrets.CustomBaseUrl or ""):gsub("/+$", "")
	if baseUrl == "" then return nil end
	local deletePath = tostring(customStorageConfig.DeletePath or "/api/mphone/photos/")
	return baseUrl .. deletePath .. photoId .. "?token=" .. deleteToken
end

local function ReplySaveFailure(controller, requestId, errorText, storageKey)
	Reply(controller, requestId, false, errorText, {
		remoteDeleteUrl = GetRemoteDeleteUrl(storageKey),
	})
end

local function GetUploadTarget()
	local storageMode = tostring(storageConfig.Mode or ""):lower()
	if storageMode ~= "custom" then return nil, "upload_provider_requires_native_http" end
	local baseUrl = tostring(storageSecrets.CustomBaseUrl or ""):gsub("/+$", "")
	if baseUrl == "" then return nil, "upload_not_configured" end
	local endpoint = baseUrl .. tostring(customStorageConfig.UploadTicketPath or "/api/mphone/photos/upload-ticket")
	local isSecure = endpoint:match("^https://") ~= nil
	local isLoopback = endpoint:match("^http://127%.0%.0%.1[:/]") ~= nil
		or endpoint:match("^http://localhost[:/]") ~= nil
	if not isSecure and not isLoopback then return nil, "upload_requires_https" end
	return endpoint
end

RegisterServerEvent("m-phone:camera:uploadTicket", function(a, b)
	local controller, _, requestId, playerId = Resolve(a, b)
	Core.SInfo("Camera upload ticket event", { requestId = requestId, playerId = playerId })
	if playerId == "" then Reply(controller, requestId, false, "player_not_found") return end
	local storageMode = tostring(storageConfig.Mode or ""):lower()
	if storageMode ~= "custom" and storageMode ~= "fivemanage" then
		Reply(controller, requestId, false, "upload_not_configured")
		return
	end
	local ticketEndpoint, errorText = GetUploadTarget()
	if not ticketEndpoint then
		Core.SWarn("Camera upload configuration rejected", { requestId = requestId, error = errorText })
		Reply(controller, requestId, false, errorText or "upload_not_configured")
		return
	end
	local ticketId = ("upload-%s-%s"):format(tostring(os.time()), tostring(math.random(100000, 999999)))
	uploadTickets[playerId] = { id = ticketId, expiresAt = os.time() + 120 }
	Reply(controller, requestId, true, nil, {
		ticketEndpoint = ticketEndpoint,
		uploadMethod = "raw",
		uploadTicket = ticketId,
	})
end)

RegisterServerEvent("m-phone:camera:list", function(a, b)
	local controller, payload, requestId, playerId = Resolve(a, b)
	if playerId == "" then Reply(controller, requestId, false, "player_not_found") return end
	if not DB or not DB.Photos then Reply(controller, requestId, false, "database_unavailable") return end
	local photos = DB.Photos.List(playerId, payload.limit, payload.offset)
	Reply(controller, requestId, true, nil, { photos = photos, total = DB.Photos.Count(playerId) })
end)

RegisterServerEvent("m-phone:camera:save", function(a, b)
	local controller, payload, requestId, playerId = Resolve(a, b)
	Core.SInfo("Camera save event", { requestId = requestId, playerId = playerId })
	if playerId == "" then Reply(controller, requestId, false, "player_not_found") return end
	local url = tostring(payload.url or "")
	local storageKey = tostring(payload.storageKey or "")
	if not IsValidUrl(url, storageKey) then Reply(controller, requestId, false, "invalid_photo_url") return end
	local issuedTicket = uploadTickets[playerId]
	if not issuedTicket
		or issuedTicket.id ~= tostring(payload.uploadTicket or "")
		or tonumber(issuedTicket.expiresAt or 0) < os.time()
	then
		ReplySaveFailure(controller, requestId, "invalid_upload_ticket", storageKey)
		return
	end
	uploadTickets[playerId] = nil
	if not DB or not DB.Photos then
		ReplySaveFailure(controller, requestId, "database_unavailable", storageKey)
		return
	end
	local now = os.time()
	if recentSaves[playerId] and now - recentSaves[playerId] < 1 then
		ReplySaveFailure(controller, requestId, "capture_rate_limited", storageKey)
		return
	end
	local maxPhotos = math.max(1, math.floor(tonumber(cameraConfig.MaxPhotos) or 200))
	if DB.Photos.Count(playerId) >= maxPhotos then
		ReplySaveFailure(controller, requestId, "gallery_full", storageKey)
		return
	end

	local photo = {
		id = ("photo-%s-%s"):format(tostring(now), tostring(math.random(100000, 999999))),
		playerId = playerId,
		url = url,
		storageKey = storageKey,
		source = tostring(payload.source or "camera"),
		width = tonumber(payload.width) or 0,
		height = tonumber(payload.height) or 0,
		createdAt = now,
	}
	photo.width = math.max(1, math.min(4096, math.floor(photo.width)))
	photo.height = math.max(1, math.min(4096, math.floor(photo.height)))
	if not DB.Photos.Create(photo) then
		Core.SWarn("Camera DB save failed", { requestId = requestId, playerId = playerId })
		ReplySaveFailure(controller, requestId, "photo_save_failed", storageKey)
		return
	end
	recentSaves[playerId] = now
	Timer.SetTimeout(function()
		if recentSaves[playerId] == now then recentSaves[playerId] = nil end
	end, 5000)
	Reply(controller, requestId, true, nil, { photo = photo })
	Core.SInfo("Camera photo saved", { requestId = requestId, photoId = photo.id, playerId = playerId })
end)

RegisterServerEvent("m-phone:camera:delete", function(a, b)
	local controller, payload, requestId, playerId = Resolve(a, b)
	if playerId == "" then Reply(controller, requestId, false, "player_not_found") return end
	if not DB or not DB.Photos then Reply(controller, requestId, false, "database_unavailable") return end
	local photoId = tostring(payload.photoId or "")
	if photoId == "" then Reply(controller, requestId, false, "invalid_photo_id") return end
	local photo = DB.Photos.Get(playerId, photoId)
	if not photo then Reply(controller, requestId, false, "photo_not_found") return end
	if not DB.Photos.Delete(playerId, photoId) then Reply(controller, requestId, false, "photo_delete_failed") return end
	Reply(controller, requestId, true, nil, {
		photoId = photoId,
		remoteDeleteUrl = GetRemoteDeleteUrl(photo.storageKey),
	})
end)

Core.SInfo("Camera server loaded", { maxPhotos = tonumber(cameraConfig.MaxPhotos) or 200 })
