local Core = _G.MPhoneClient
if not Core or not Core.UI then
	print("[m-phone][Camera][error] _G.MPhoneClient (or UI) not found")
	return
end

local UI = Core.UI
local cameraConfig = type(Config.Camera) == "table" and Config.Camera or {}
local storageConfig = type(cameraConfig.Storage) == "table" and cameraConfig.Storage or {}
local capture = nil
local previewRoot = nil
local previewImage = nil
local previewViewportSubsystem = nil
local previewLayout = nil
local previewLayoutLogSignature = nil
local cameraMode = nil
local cameraRotation = Rotator(0, 0, 0)
local cameraFov = 60
local captureWidth = math.max(128, math.floor(tonumber(cameraConfig.CaptureWidth) or 720))
local captureHeight = math.max(128, math.floor(tonumber(cameraConfig.CaptureHeight) or 900))
local rotationTimer = nil
local pending = {}
local sequence = 0
local serverRequestTimeoutMs = math.max(1000, math.floor(tonumber(cameraConfig.ServerRequestTimeoutMs) or 20000))
local base64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local offsets = {
	front = {
		location = Vector(45, -2, 65),
		rotation = Rotator(0, 180, 0),
	},
	rear = {
		location = Vector(25, 0, 165),
		rotation = Rotator(0, 0, 0),
	},
}

local zoomFov = { [0.6] = 90, [1] = 60, [2] = 30, [5] = 12 }

local function NextRequestId(kind)
	sequence = sequence + 1
	return ("%s-camera-%s-%s"):format(tostring(os.time()), tostring(kind or "request"), tostring(sequence))
end

local function Clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function IsObjectValid(object)
	if not object then return false end
	local ok, valid = pcall(function() return object:IsValid() end)
	return ok and valid ~= false
end

local function GetCharacter()
	local ok, pawn = pcall(GetPlayerPawn)
	return ok and pawn or nil
end

local function GetGameViewportSubsystem()
	local ok, subsystem = pcall(function()
		return UE.UGameViewportSubsystem.Get(HWorld)
	end)
	if ok and subsystem then return subsystem end

	ok, subsystem = pcall(function()
		return UE.UGameViewportSubsystem.Get()
	end)
	if ok and subsystem then return subsystem end

	ok, subsystem = pcall(function()
		local subsystemClass = UE.UClass.Load("/Script/UMG.GameViewportSubsystem")
		return UE.USubsystemBlueprintLibrary.GetEngineSubsystem(subsystemClass)
	end)
	return ok and subsystem or nil
end

local function ResolveNativeLayout(layout)
	layout = type(layout) == "table" and layout or {}
	local x = tonumber(layout.x) or 0
	local y = tonumber(layout.y) or 0
	local width = tonumber(layout.width) or 32
	local height = tonumber(layout.height) or 32
	local webWidth = tonumber(layout.viewportWidth) or 0
	local webHeight = tonumber(layout.viewportHeight) or 0
	local viewportWidth = webWidth
	local viewportHeight = webHeight
	local viewportScale = 1
	local character = GetCharacter()
	if character then
		pcall(function()
			local viewport = UE.UWidgetLayoutLibrary.GetViewportSize(character)
			if viewport then
				viewportWidth = tonumber(viewport.X) or viewportWidth
				viewportHeight = tonumber(viewport.Y) or viewportHeight
			end
		end)
		pcall(function()
			viewportScale = tonumber(UE.UWidgetLayoutLibrary.GetViewportScale(character)) or 1
		end)
	end
	if webWidth > 0 and webHeight > 0 and viewportWidth > 0 and viewportHeight > 0 then
		local scaleX = viewportWidth / webWidth
		local scaleY = viewportHeight / webHeight
		x = x * scaleX
		y = y * scaleY
		width = width * scaleX
		height = height * scaleY
	end
	return x, y, width, height, viewportWidth, viewportHeight, math.max(0.01, viewportScale)
end

local function Reply(callback, payload, uiRequestId)
	if uiRequestId and tostring(uiRequestId) ~= "" then
		UI:SendEvent("camera:uiResult", {
			uiRequestId = tostring(uiRequestId),
			result = payload,
		})
	end
	if callback then
		local ok, errorText = pcall(function()
			callback(payload)
		end)
		if not ok then
			Core.LogWarn("Camera callback failed", "m-phone", { error = tostring(errorText) })
		end
	end
end

local function ApplyPreviewLayout(layout)
	if type(layout) == "table" then previewLayout = layout end
	layout = previewLayout
	if not previewImage or type(layout) ~= "table" then return end
	local x, y, width, height, viewportWidth, viewportHeight, viewportScale = ResolveNativeLayout(layout)
	x = Clamp(x, -10000, 10000)
	y = Clamp(y, -10000, 10000)
	width = Clamp(width, 32, 4096)
	height = Clamp(height, 32, 4096)
	local signature = ("%dx%d:%d,%d,%d,%d"):format(
		math.floor(viewportWidth), math.floor(viewportHeight),
		math.floor(x), math.floor(y), math.floor(width), math.floor(height)
	)
	if signature ~= previewLayoutLogSignature then
		previewLayoutLogSignature = signature
		Core.LogInfo((
			"Camera preview layout | UE=%.0fx%.0f WEB=%.0fx%.0f " ..
			"RAW_POS=%.0f,%.0f RAW_SIZE=%.0f,%.0f PHONE=%.0f,%.0f " ..
			"OFFSET=%.0f,%.0f FINAL_POS=%.0f,%.0f FINAL_SIZE=%.0f,%.0f"
		):format(
			viewportWidth, viewportHeight,
			tonumber(layout.viewportWidth) or 0, tonumber(layout.viewportHeight) or 0,
			tonumber(layout.x) or 0, tonumber(layout.y) or 0,
			tonumber(layout.width) or 0, tonumber(layout.height) or 0,
			tonumber(layout.phoneWidth) or 0, tonumber(layout.phoneHeight) or 0,
			tonumber(layout.previewOffsetX) or 0, tonumber(layout.previewOffsetY) or 0,
			x, y, width, height
		), "m-phone")
	end
	local viewportSubsystem = previewViewportSubsystem
	local root = previewRoot
	if not IsObjectValid(viewportSubsystem) or not IsObjectValid(root) then return false end

	local ok = pcall(function()
		local slot = viewportSubsystem:GetWidgetSlot(root)
		slot = UE.UGameViewportSubsystem.SetWidgetSlotPosition(
			slot,
			root,
			Vector2D(x, y),
			true
		)
		slot = UE.UGameViewportSubsystem.SetWidgetSlotDesiredSize(
			slot,
			Vector2D(width / viewportScale, height / viewportScale)
		)
		slot.Alignment = Vector2D(0, 0)
		slot.ZOrder = 900
		viewportSubsystem:SetWidgetSlot(root, slot)
	end)
	return ok
end

local function ApplyCameraTransform(mode)
	if not capture or not capture.Object then return false end
	local transform = offsets[mode] or offsets.front
	cameraRotation = Rotator(transform.rotation.Pitch, transform.rotation.Yaw, transform.rotation.Roll)
	local locationOk = pcall(function()
		capture.Object:K2_SetActorRelativeLocation(transform.location, false, nil, false)
	end)
	local rotationOk = pcall(function()
		capture.Object:K2_SetActorRelativeRotation(cameraRotation, false, nil, false)
	end)
	return locationOk and rotationOk
end

local function ApplyCameraRotation()
	if not capture or not capture.Object then return false end
	return pcall(function()
		capture.Object:K2_SetActorRelativeRotation(cameraRotation, false, nil, false)
	end)
end

local function ApplyCameraFov(value)
	cameraFov = Clamp(value, 12, 100)
	if not capture or not capture.Object then return false end
	local updated = false
	local ok = pcall(function()
		local component = capture.Object:GetComponentByClass(UE.USceneCaptureComponent2D.StaticClass())
		if component then
			component.FOVAngle = cameraFov
			updated = true
		end
	end)
	return ok and updated
end

local function ApplyCameraExposure(mode)
	if not capture or not capture.Component then return false end
	local bias = mode == "front"
		and (tonumber(cameraConfig.SelfieExposureBias) or 0.8)
		or (tonumber(cameraConfig.RearExposureBias) or 0)
	return pcall(function()
		local settings = capture.Component.PostProcessSettings
		settings.bOverride_AutoExposureBias = true
		settings.AutoExposureBias = bias
		capture.Component.PostProcessSettings = settings
		capture.Component.PostProcessBlendWeight = 1
	end)
end

local function AdjustCamera(payload)
	payload = type(payload) == "table" and payload or {}
	cameraRotation.Yaw = cameraRotation.Yaw + Clamp(tonumber(payload.yaw) or 0, -30, 30)
	cameraRotation.Pitch = Clamp(cameraRotation.Pitch + Clamp(tonumber(payload.pitch) or 0, -30, 30), -70, 70)
	cameraRotation.Roll = Clamp(cameraRotation.Roll + Clamp(tonumber(payload.roll) or 0, -30, 30), -45, 45)
	local rotationOk = ApplyCameraRotation()
	local fovDelta = tonumber(payload.fovDelta) or 0
	local fovOk = fovDelta == 0 or ApplyCameraFov(cameraFov + Clamp(fovDelta, -20, 20))
	return rotationOk and fovOk
end

local function UpdateCameraRotation()
	if not capture or not capture.Object or cameraMode ~= "rear" then return end
	local okController, controller = pcall(function()
		return UE.UGameplayStatics.GetPlayerController(capture.Object, 0)
	end)
	if not okController or not controller then return end
	local okDelta, deltaX, deltaY = pcall(function()
		return controller:GetInputMouseDelta()
	end)
	if not okDelta then return end
	deltaX = tonumber(deltaX) or 0
	deltaY = tonumber(deltaY) or 0
	if math.abs(deltaX) < 0.001 and math.abs(deltaY) < 0.001 then return end
	cameraRotation.Yaw = cameraRotation.Yaw + deltaX * 0.2
	cameraRotation.Pitch = Clamp(cameraRotation.Pitch - deltaY * 0.2, -45, 45)
	ApplyCameraRotation()
end

local function UpdateRotationTimer()
	if rotationTimer then
		pcall(function() Timer.ClearInterval(rotationTimer) end)
		rotationTimer = nil
	end
	if cameraMode == "rear" and capture and capture.Object then
		rotationTimer = Timer.SetInterval(UpdateCameraRotation, 33)
	end
end

local function DestroyCapture()
	if rotationTimer then
		pcall(function() Timer.ClearInterval(rotationTimer) end)
		rotationTimer = nil
	end
	if previewViewportSubsystem and previewRoot then
		pcall(function() previewViewportSubsystem:RemoveWidget(previewRoot) end)
	elseif previewRoot then
		pcall(function() previewRoot:RemoveFromParent() end)
	end
	if previewRoot then pcall(function() previewRoot:RemoveFromRoot() end) end
	if capture and capture.Object then pcall(function() capture.Object:K2_DestroyActor() end) end
	previewRoot = nil
	previewImage = nil
	previewViewportSubsystem = nil
	previewLayout = nil
	previewLayoutLogSignature = nil
	capture = nil
end

local function CloseCamera()
	local character = GetCharacter()
	if character and cameraMode then
		pcall(function() UE.UHRoleplaySystemGlobals.ClosePhoneCamera(character) end)
	end
	DestroyCapture()
	cameraMode = nil
end

local function ResolveCaptureSize(layout)
	local width = math.max(128, math.floor(tonumber(cameraConfig.CaptureWidth) or 720))
	local fallbackHeight = math.max(128, math.floor(tonumber(cameraConfig.CaptureHeight) or 900))
	if type(layout) ~= "table" then return width, fallbackHeight end

	local previewWidth = tonumber(layout.width) or 0
	local previewHeight = tonumber(layout.height) or 0
	if previewWidth < 32 or previewHeight < 32 then return width, fallbackHeight end

	local aspect = Clamp(previewHeight / previewWidth, 0.75, 2.0)
	local height = math.max(128, math.floor(width * aspect + 0.5))
	if height % 2 ~= 0 then height = height + 1 end
	return width, height
end

local function BuildCapture(layout)
	local character = GetCharacter()
	if not character then return false, "character_unavailable" end

	captureWidth, captureHeight = ResolveCaptureSize(layout)
	local width, height = captureWidth, captureHeight
	local okCapture, result = pcall(function()
		return SceneCapture(
			Vector(0, 0, 0),
			Rotator(0, 0, 0),
			width,
			height,
			SceneCaptureSource.FinalColorLDR,
			false
		)
	end)
	if not okCapture or not result or not result.Object or not result.RenderTarget then
		return false, "scene_capture_failed"
	end
	capture = result

	local attachOk, attached = pcall(function()
		return AttachActorToActor(
			capture.Object,
			character,
			Vector(0, 0, 0),
			Rotator(0, 0, 0)
		)
	end)
	if not attachOk or attached == false then DestroyCapture() return false, "camera_attach_failed" end

	pcall(function()
		local component = capture.Component
		if component then
			component.FOVAngle = cameraFov
			component.bCaptureEveryFrame = true
			component.bCaptureOnMovement = true
		end
	end)

	local okWidget, widgetError = pcall(function()
		previewViewportSubsystem = GetGameViewportSubsystem()
		assert(previewViewportSubsystem, "game viewport subsystem unavailable")

		previewImage = UE.NewObject(UE.UImage, HWorld)
		previewRoot = previewImage
		assert(previewImage, "native camera preview widget creation failed")
		pcall(function() previewImage:AddToRoot() end)
		previewImage:SetBrushResourceObject(capture.RenderTarget)

		local viewportSlot = UE.FGameViewportWidgetSlot()
		viewportSlot.ZOrder = 900
		assert(previewViewportSubsystem:AddWidget(previewRoot, viewportSlot), "camera preview viewport add failed")
		ApplyPreviewLayout(layout)
	end)
	if not okWidget then
		Core.LogWarn("Camera preview widget failed", "m-phone", { error = tostring(widgetError) })
		DestroyCapture()
		return false, "preview_widget_failed"
	end

	return true
end

local function SetCameraMode(mode, layout)
	mode = mode == "rear" and "rear" or "front"
	local character = GetCharacter()
	if not character then return false, "character_unavailable" end

	if cameraMode and cameraMode ~= mode then
		pcall(function() UE.UHRoleplaySystemGlobals.ClosePhoneCamera(character) end)
		cameraMode = nil
	end

	if cameraMode ~= mode then
		local opened = pcall(function()
			if mode == "front" then
				UE.UHRoleplaySystemGlobals.OpenPhoneFrontCamera(character)
			else
				UE.UHRoleplaySystemGlobals.OpenPhoneBackCamera(character)
			end
		end)
		if not opened then return false, "phone_camera_animation_failed" end
		cameraMode = mode
	end

	if not capture then
		local built, buildError = BuildCapture(layout)
		if not built then CloseCamera() return false, buildError end
	end

	ApplyPreviewLayout(layout)
	if not ApplyCameraTransform(mode) then CloseCamera() return false, "camera_transform_failed" end
	ApplyCameraExposure(mode)
	UpdateRotationTimer()
	return true
end

local function SendServerRequest(eventName, kind, payload, callback)
	payload = type(payload) == "table" and payload or {}
	local requestId = NextRequestId(kind)
	payload.requestId = requestId
	pending[requestId] = callback
	Core.LogInfo("Camera server request", "m-phone", { event = eventName, requestId = requestId })
	TriggerServerEvent(eventName, payload)
	Timer.SetTimeout(function()
		local timedOutCallback = pending[requestId]
		if not timedOutCallback then return end
		pending[requestId] = nil
		Core.LogWarn("Camera server request timed out", "m-phone", { event = eventName, requestId = requestId })
		Reply(timedOutCallback, { ok = false, error = "server_timeout" })
	end, serverRequestTimeoutMs)
end

RegisterClientEvent("m-phone:camera:result", function(payload)
	payload = type(payload) == "table" and payload or {}
	local requestId = tostring(payload.requestId or "")
	local callback = pending[requestId]
	pending[requestId] = nil
	Core.LogInfo("Camera server response", "m-phone", {
		requestId = requestId,
		ok = payload.ok == true,
		error = tostring(payload.error or ""),
	})
	Reply(callback, payload)
end)

local function GetLocalPhotoDirectory()
	local relativePath = tostring(storageConfig.LocalDirectory or "MPhone/Photos/")
		:gsub("\\", "/")
		:gsub("^/+", "")
	if relativePath:sub(-1) ~= "/" then relativePath = relativePath .. "/" end
	return UE.UKismetSystemLibrary.GetProjectSavedDirectory():gsub("\\", "/") .. relativePath
end

local function GetFileSize(path)
	local file = io.open(path, "rb")
	if not file then return nil end
	local size = file:seek("end")
	file:close()
	return tonumber(size)
end

local function EncodeBase64(data)
	local output = {}
	local length = #data
	local outputIndex = 1
	for index = 1, length, 3 do
		local first = data:byte(index) or 0
		local second = data:byte(index + 1)
		local third = data:byte(index + 2)
		local value = first * 65536 + (second or 0) * 256 + (third or 0)
		output[outputIndex] = base64Alphabet:sub(math.floor(value / 262144) % 64 + 1, math.floor(value / 262144) % 64 + 1)
		output[outputIndex + 1] = base64Alphabet:sub(math.floor(value / 4096) % 64 + 1, math.floor(value / 4096) % 64 + 1)
		output[outputIndex + 2] = second and base64Alphabet:sub(math.floor(value / 64) % 64 + 1, math.floor(value / 64) % 64 + 1) or "="
		output[outputIndex + 3] = third and base64Alphabet:sub(value % 64 + 1, value % 64 + 1) or "="
		outputIndex = outputIndex + 4
	end
	return table.concat(output)
end

local function StreamCapturedPhoto(filePath, ticketData, callback)
	local file = io.open(filePath, "rb")
	if not file then
		Reply(callback, { ok = false, error = "capture_file_unavailable" })
		return
	end
	local fileSize = GetFileSize(filePath) or 0
	local transferId = NextRequestId("transfer")
	local chunkIndex = 0
	UI:SendEvent("camera:uploadBegin", {
		transferId = transferId,
		totalBytes = fileSize,
	})

	local function SendNextChunk()
		local data = file:read(24576)
		if data and #data > 0 then
			chunkIndex = chunkIndex + 1
			UI:SendEvent("camera:uploadChunk", {
				transferId = transferId,
				index = chunkIndex,
				data = EncodeBase64(data),
			})
			Timer.SetTimeout(SendNextChunk, 1)
			return
		end

		file:close()
		pcall(os.remove, filePath)
		UI:SendEvent("camera:uploadEnd", {
			transferId = transferId,
			chunks = chunkIndex,
		})
		Core.LogInfo("Camera photo transferred to WebUI", "m-phone", {
			bytes = fileSize,
			chunks = chunkIndex,
		})
		Reply(callback, {
			ok = true,
			data = {
				transferId = transferId,
				ticketEndpoint = tostring(ticketData.ticketEndpoint or ""),
				uploadMethod = tostring(ticketData.uploadMethod or "raw"),
				uploadTicket = tostring(ticketData.uploadTicket or ""),
				width = captureWidth,
				height = captureHeight,
			},
		})
	end
	Timer.SetTimeout(SendNextChunk, 1)
end

local function SaveCapturedPhoto(filePath, callback)
	local storageMode = tostring(storageConfig.Mode or ""):lower()
	if storageMode ~= "custom" and storageMode ~= "fivemanage" then
		pcall(os.remove, filePath)
		Reply(callback, { ok = false, error = "upload_not_configured" })
		return
	end
	Core.LogInfo("Camera remote upload starting", "m-phone", { provider = storageMode })

	SendServerRequest("m-phone:camera:uploadTicket", "upload-ticket", {}, function(ticketResult)
		local ticketData = type(ticketResult) == "table" and type(ticketResult.data) == "table" and ticketResult.data or nil
		local ticketEndpoint = ticketData and tostring(ticketData.ticketEndpoint or "") or ""
		local uploadTicket = ticketData and tostring(ticketData.uploadTicket or "") or ""
		if type(ticketResult) ~= "table" or ticketResult.ok ~= true or ticketEndpoint == "" or uploadTicket == "" then
			Core.LogWarn("Camera upload ticket failed", "m-phone", {
				error = tostring(type(ticketResult) == "table" and ticketResult.error or "invalid_response"),
			})
			pcall(os.remove, filePath)
			Reply(callback, ticketResult or { ok = false, error = "upload_ticket_failed" })
			return
		end
		StreamCapturedPhoto(filePath, ticketData, callback)
	end)
end

UI:RegisterEventHandler("camera:open", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	local ok, errorText = SetCameraMode(payload.facing, payload.layout)
	Reply(callback, { ok = ok, error = errorText }, payload.uiRequestId)
end)

UI:RegisterEventHandler("camera:setFacing", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	local ok, errorText = SetCameraMode(payload.facing, payload.layout)
	Reply(callback, { ok = ok, error = errorText }, payload.uiRequestId)
end)

UI:RegisterEventHandler("camera:setLayout", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	local applied = capture ~= nil and ApplyPreviewLayout(payload.layout) == true
	Reply(callback, { ok = applied }, payload.uiRequestId)
end)

UI:RegisterEventHandler("camera:setZoom", function(payload, callback)
	local zoom = tonumber(type(payload) == "table" and payload.zoom) or 1
	local fov = zoomFov[zoom] or 60
	local ok = ApplyCameraFov(fov)
	Reply(callback, { ok = ok == true, zoom = zoom }, type(payload) == "table" and payload.uiRequestId)
end)

UI:RegisterEventHandler("camera:adjust", function(payload, callback)
	local ok = AdjustCamera(payload)
	Reply(callback, { ok = ok == true, fov = cameraFov }, type(payload) == "table" and payload.uiRequestId)
end)

UI:RegisterEventHandler("camera:reset", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	local ok = ApplyCameraTransform(cameraMode or "front")
	ApplyCameraFov(60)
	Reply(callback, { ok = ok == true, fov = cameraFov }, payload.uiRequestId)
end)

UI:RegisterEventHandler("camera:capture", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	local function respond(result) Reply(callback, result, payload.uiRequestId) end
	if not capture or not capture.RenderTarget then respond({ ok = false, error = "camera_not_ready" }) return end
	local character = GetCharacter()
	if not character then respond({ ok = false, error = "character_unavailable" }) return end
	local activeCapture = capture
	Timer.SetTimeout(function()
		if capture ~= activeCapture or not activeCapture.RenderTarget then
			respond({ ok = false, error = "camera_closed" })
			return
		end
		local saveDir = GetLocalPhotoDirectory()
		local fileName = ("photo_%s_%s.png"):format(tostring(os.time()), tostring(math.random(100000, 999999)))
		local okExport = pcall(function()
			UE.UKismetRenderingLibrary.ExportRenderTarget(character, activeCapture.RenderTarget, saveDir, fileName)
		end)
		if not okExport then respond({ ok = false, error = "capture_export_failed" }) return end
		local localPath = (saveDir .. fileName):gsub("\\", "/")
		local fileSize = GetFileSize(localPath)
		if not fileSize or fileSize <= 0 then
			Core.LogWarn("Camera export produced no local file", "m-phone", { path = localPath })
			respond({ ok = false, error = "capture_file_missing" })
			return
		end
		Core.LogInfo("Camera photo saved locally", "m-phone", {
			path = localPath,
			bytes = fileSize,
		})
		SaveCapturedPhoto(localPath, respond)
	end, 80)
end)

UI:RegisterEventHandler("camera:commit", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	SendServerRequest("m-phone:camera:save", "save", {
		url = tostring(payload.url or ""),
		storageKey = tostring(payload.storageKey or ""),
		uploadTicket = tostring(payload.uploadTicket or ""),
		source = "camera_remote",
		width = tonumber(payload.width) or captureWidth,
		height = tonumber(payload.height) or captureHeight,
	}, function(result)
		Reply(callback, result, payload.uiRequestId)
	end)
end)

UI:RegisterEventHandler("camera:close", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	CloseCamera()
	Reply(callback, { ok = true }, payload.uiRequestId)
end)

UI:RegisterEventHandler("gallery:list", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	SendServerRequest("m-phone:camera:list", "list", payload, function(result)
		Reply(callback, result, payload.uiRequestId)
	end)
end)

UI:RegisterEventHandler("gallery:delete", function(payload, callback)
	payload = type(payload) == "table" and payload or {}
	SendServerRequest("m-phone:camera:delete", "delete", payload, function(result)
		Reply(callback, result, payload.uiRequestId)
	end)
end)

_G.MPhoneCamera = {
	Close = CloseCamera,
}
Core.LogInfo("Camera client loaded", "m-phone")
