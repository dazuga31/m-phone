local ButtonAnimation = require("WorldSystems.ParkingMeter.button_animation")

local Core = _G.MPhoneClient
local ParkingMeter = {
	Meters = {},
	ByActor = {},
	ActiveMeterId = nil,
	NearbyMeterId = nil,
	ProximityTimer = nil,
	DisplayTimer = nil,
}

local MeterConfig = type(Config) == "table" and type(Config.ParkingMeter) == "table" and Config.ParkingMeter or {}
local DEFAULT_MINUTES = math.max(0, math.floor(tonumber(MeterConfig.DefaultMinutes) or 30))
local MINUTES_STEP = math.max(1, math.floor(tonumber(MeterConfig.MinutesStep) or 15))
local MAX_MINUTES = math.max(MINUTES_STEP, math.floor(tonumber(MeterConfig.MaxMinutes) or 240))
local PROXIMITY_INTERVAL = 150
local DISPLAY_INTERVAL = 1000
local RequestSequence = 0
local PRICE_PER_STEP = math.max(0, tonumber(MeterConfig.PricePerStep) or 15)
local NextRequestId
local RemainingSeconds
local FormatDuration

local BUTTON_ACTIONS = {
	Button_1 = "increase",
	Button_2 = "confirm",
	Button_3 = "back",
	Button_4 = "decrease",
}

local function Log(level, message, payload)
	if not Core then return end
	local logger = level == "warn" and Core.LogWarn or Core.LogInfo
	if type(logger) == "function" then logger(message, "m-phone:parking-meter", payload) end
end

local function ComponentName(component)
	local ok, name = pcall(function() return component:GetName() end)
	name = ok and tostring(name) or ""
	return name:gsub("_GEN_VARIABLE$", "")
end

local function SetComponentVisible(component, visible)
	if not component then return end
	pcall(function() component:SetHiddenInGame(not visible, true) end)
	pcall(function() component:SetVisibility(visible, true) end)
end

local function SetText(component, value)
	if not component then return false end
	local ok = pcall(function() component:SetText(tostring(value or "")) end)
	return ok
end

local function GetController()
	if type(GetPlayerController) == "function" then
		local ok, controller = pcall(GetPlayerController)
		if ok and controller then return controller end
	end
	if UE and UE.UGameplayStatics then
		local ok, controller = pcall(function()
			return UE.UGameplayStatics.GetPlayerController(HWorld, 0)
		end)
		if ok then return controller end
	end
	return nil
end

local function SetInteractionMode(enabled)
	local controller = GetController()
	if not controller then return false, "player_controller_unavailable" end
	if enabled == true then
		pcall(function() controller:SetIgnoreMoveInput(true) end)
		pcall(function() controller:SetIgnoreLookInput(true) end)
	else
		pcall(function() controller:SetIgnoreMoveInput(false) end)
		pcall(function() controller:SetIgnoreLookInput(false) end)
	end
	return true
end

local function ComponentTransform(component)
	local okLocation, location = pcall(function() return component:K2_GetComponentLocation() end)
	local okRotation, rotation = pcall(function() return component:K2_GetComponentRotation() end)
	if not okLocation or not location or not okRotation or not rotation then return nil end
	-- Imported FBX parts share one component origin while their vertices retain
	-- baked offsets. Primitive bounds provide the actual visible part center.
	pcall(function()
		if component.Bounds and component.Bounds.Origin then
			location = component.Bounds.Origin
		end
	end)
	return {
		location = location,
		rotation = rotation,
	}
end

local function AddComponentsByClass(actor, classPath, result)
	local class = LoadClass(classPath)
	if not class then return false end
	local ok, components = pcall(function() return GetComponentsByClass(actor, class) end)
	if not ok or not components then return false end
	for _, component in pairs(components) do
		result[ComponentName(component)] = component
	end
	return true
end

local function FindComponents(actor)
	if not actor or type(LoadClass) ~= "function" or type(GetComponentsByClass) ~= "function" then
		return nil, "component_api_unavailable"
	end
	local result = {}
	if not AddComponentsByClass(actor, "/Script/Engine.StaticMeshComponent", result) then
		return nil, "static_mesh_components_unavailable"
	end
	AddComponentsByClass(actor, "/Script/Engine.TextRenderComponent", result)
	return result
end

local function CopyTable(source)
	local result = {}
	for key, value in pairs(type(source) == "table" and source or {}) do result[key] = value end
	return result
end

local function BuildSpatialDefinition(meter)
	local screenTransform = ComponentTransform(meter.components.PayScreen)
	if not screenTransform then return nil, "pay_screen_transform_unavailable" end
	local location = screenTransform.location
	local rotation = screenTransform.rotation
	local defaults = Config and Config.ParkingMeter and Config.ParkingMeter.Spatial or {}
	local overrides = type(meter.definition.spatial) == "table" and meter.definition.spatial or {}
	local spatial = CopyTable(defaults)
	for key, value in pairs(overrides) do spatial[key] = value end
	spatial.enabled = true
	spatial.mode = "parking-meter"
	spatial.frame = "parking-meter"
	spatial.renderOnSurface = false

	return {
		id = meter.id,
		transform = {
			x = location.X,
			y = location.Y,
			z = location.Z,
			pitch = rotation.Pitch,
			yaw = rotation.Yaw,
			roll = rotation.Roll,
		},
		spatial = spatial,
	}
end

function ParkingMeter.OpenById(id)
	local meter = ParkingMeter.Meters[tostring(id or "")]
	if not meter then return false, "meter_not_found" end
	TriggerServerEvent("m-phone:parkingMeter:getState", {
		requestId = NextRequestId(),
		meterId = meter.id,
	})
	return ParkingMeter.Open(BuildSpatialDefinition(meter))
end

function ParkingMeter.Open(definition, buildError)
	if not definition then return false, buildError or "invalid_definition" end
	if not Core or not Core.ActivateNativeSpatial then
		return false, "m_phone_native_spatial_runtime_unavailable"
	end
	local ok, reason = Core.ActivateNativeSpatial(definition)
	if not ok then return false, reason end
	ParkingMeter.ActiveMeterId = tostring(definition.id or "")
	local meter = ParkingMeter.Meters[ParkingMeter.ActiveMeterId]
	if meter then
		SetComponentVisible(meter.components.InteractText, false)
		if meter.refreshDisplay then meter.refreshDisplay() end
	end
	SetInteractionMode(true)
	return true
end

local function FormatClock(minutes)
	minutes = math.max(0, tonumber(minutes) or 0)
	local hours = math.floor(minutes / 60)
	local remainder = minutes % 60
	return string.format("%02d:%02d", hours, remainder)
end

local function BuildDisplayText(meter)
	local state = meter.state
	local active = state.expiresAt and RemainingSeconds(meter) > 0
	local status = state.pending and "PROCESSING" or (state.errorText or state.paymentText or (active and ("ACTIVE " .. FormatDuration(RemainingSeconds(meter))) or "SELECT TIME"))
	local price = math.floor((state.minutes or 0) / MINUTES_STEP) * PRICE_PER_STEP
	return table.concat({
		"PARKING METER",
		string.format("%s%s   $%d", active and "ADD " or "", FormatClock(state.minutes), price),
		status,
		string.format("+%d   OK   BACK   -%d", MINUTES_STEP, MINUTES_STEP),
	}, "\n")
end

RemainingSeconds = function(meter)
	local state = meter.state
	if not state.expiresAt then return math.max(0, math.floor((state.minutes or 0) * 60)) end
	local now = os.time()
	return math.max(0, math.floor(tonumber(state.expiresAt) - now))
end

FormatDuration = function(seconds)
	seconds = math.max(0, tonumber(seconds) or 0)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainder = math.floor(seconds % 60)
	if hours > 0 then return string.format("%02d:%02d:%02d", hours, minutes, remainder) end
	return string.format("%02d:%02d", minutes, remainder)
end

NextRequestId = function()
	RequestSequence = RequestSequence + 1
	return string.format("parking_%d_%d", os.time(), RequestSequence)
end

local function BuildAboveMeterText(meter)
	if RemainingSeconds(meter) <= 0 then
		return "PARKING METER\nAVAILABLE"
	end
	return table.concat({
		"PARKING METER",
		"TIME REMAINING",
		FormatDuration(RemainingSeconds(meter)),
	}, "\n")
end

local function RefreshDisplay(meter)
	local display = meter and meter.components and meter.components.MeterDisplayText or nil
	if not display then return false, "native_display_missing" end
	if meter.state.expiresAt and RemainingSeconds(meter) <= 0 then
		meter.state.confirmed = false
	end
	local ok, errorMessage = pcall(function() display:SetText(BuildDisplayText(meter)) end)
	if not ok then return false, tostring(errorMessage) end
	SetText(meter.components.AboveMeterText, BuildAboveMeterText(meter))
	return true
end

local function CloseMeter()
	local meter = ParkingMeter.Meters[ParkingMeter.ActiveMeterId or ""]
	ParkingMeter.ActiveMeterId = nil
	SetInteractionMode(false)
	if Core and Core.UI and type(Core.UI.DeactivateSpatial) == "function" then
		Core.UI:DeactivateSpatial()
	end
	if meter and ParkingMeter.NearbyMeterId == meter.id then
		SetComponentVisible(meter.components.InteractText, true)
	end
	return true
end

function ParkingMeter.PressButton(component, meter)
	local name = ComponentName(component)
	local action = BUTTON_ACTIONS[name]
	if not action then return false, "unknown_button" end
	local started, reason = ButtonAnimation.Press(component)
	if not started and reason ~= "already_animating" then
		Log("info", "Parking meter button animation skipped", { button = name, reason = reason })
	end

	meter = meter or ParkingMeter.Meters[ParkingMeter.ActiveMeterId or ""]
	if not meter then return false, "active_meter_not_found" end
	if meter.state.pending and action ~= "back" then return false, "payment_pending" end
	if action == "increase" then
		meter.state.minutes = math.min(MAX_MINUTES, meter.state.minutes + MINUTES_STEP)
		meter.state.confirmed = false
		meter.state.errorText = nil
		meter.state.paymentText = nil
	elseif action == "decrease" then
		meter.state.minutes = math.max(MINUTES_STEP, meter.state.minutes - MINUTES_STEP)
		meter.state.confirmed = false
		meter.state.errorText = nil
		meter.state.paymentText = nil
	elseif action == "confirm" then
		if meter.state.minutes <= 0 then return false, "duration_required" end
		meter.state.pending = true
		meter.state.errorText = nil
		TriggerServerEvent("m-phone:parkingMeter:pay", {
			requestId = NextRequestId(),
			meterId = meter.id,
			minutes = meter.state.minutes,
		})
	elseif action == "back" then
		return CloseMeter()
	end
	local refreshed, refreshError = RefreshDisplay(meter)
	if not refreshed then Log("warn", "Parking meter native display update failed", { error = refreshError }) end
	return true
end

function ParkingMeter.PressById(id, buttonName)
	local meter = ParkingMeter.Meters[tostring(id or "")]
	if not meter then return false, "meter_not_found" end
	local component = meter.components[tostring(buttonName or "")]
	if not component then return false, "button_not_found" end
	ParkingMeter.ActiveMeterId = meter.id
	return ParkingMeter.PressButton(component, meter)
end

local function RegisterMeter(actor, definition, index)
	local actorKey = tostring(actor)
	if ParkingMeter.ByActor[actorKey] then return true end
	local components, componentError = FindComponents(actor)
	if not components then return false, componentError end
	if not components.PayScreen then return false, "pay_screen_missing" end
	if not components.MeterDisplayText then return false, "native_display_missing" end
	for buttonName in pairs(BUTTON_ACTIONS) do
		if not components[buttonName] then return false, buttonName .. "_missing" end
		pcall(function()
			local button = components[buttonName]
			button:SetCollisionEnabled(UE.ECollisionEnabled.QueryOnly)
			button:SetCollisionResponseToAllChannels(UE.ECollisionResponse.ECR_Ignore)
			button:SetCollisionResponseToChannel(UE.ECollisionChannel.ECC_Visibility, UE.ECollisionResponse.ECR_Block)
		end)
	end
	pcall(function()
		components.PayScreen:SetHiddenInGame(false, true)
		components.PayScreen:SetVisibility(true, true)
		components.MeterDisplayText:SetHiddenInGame(false, true)
		components.MeterDisplayText:SetVisibility(true, true)
		if components.AboveMeterText then
			components.AboveMeterText:SetHiddenInGame(false, true)
			components.AboveMeterText:SetVisibility(true, true)
		end
	end)
	SetComponentVisible(components.InteractText, false)

	local id = tostring(definition.id or ("parking_meter_" .. tostring(index)))
	local meter = {
		id = id,
		actor = actor,
		components = components,
		definition = definition,
		state = {
			minutes = tonumber(definition.defaultMinutes) or DEFAULT_MINUTES,
			confirmed = false,
			expiresAt = tonumber(definition.expiresAt),
			pending = false,
			errorText = nil,
			paymentText = nil,
		},
		location = actor:K2_GetActorLocation(),
	}
	meter.refreshDisplay = function() return RefreshDisplay(meter) end
	ParkingMeter.Meters[id] = meter
	ParkingMeter.ByActor[actorKey] = meter
	RefreshDisplay(meter)
	TriggerServerEvent("m-phone:parkingMeter:getState", {
		requestId = NextRequestId(),
		meterId = id,
	})

	Log("info", "Parking meter registered", { id = id, nativeInteraction = true })
	return true
end

local function SpawnConfiguredMeter(definition)
	local blueprint = tostring(definition.blueprint or Config.ParkingMeter.Blueprint or "")
	local transformData = type(definition.transform) == "table" and definition.transform or definition
	local transform = Transform()
	transform.Translation = Vector(tonumber(transformData.x or transformData.X) or 0, tonumber(transformData.y or transformData.Y) or 0, tonumber(transformData.z or transformData.Z) or 0)
	transform.Rotation = Rotator(tonumber(transformData.pitch or transformData.Pitch) or 0, tonumber(transformData.yaw or transformData.Yaw) or 0, tonumber(transformData.roll or transformData.Roll) or 0):ToQuat()
	return SpawnActor(blueprint, transform)
end

local function DistanceBetween(a, b)
	if not a or not b then return math.huge end
	local x = (tonumber(a.X) or 0) - (tonumber(b.X) or 0)
	local y = (tonumber(a.Y) or 0) - (tonumber(b.Y) or 0)
	local z = (tonumber(a.Z) or 0) - (tonumber(b.Z) or 0)
	return math.sqrt(x * x + y * y + z * z)
end

local function GetPawnLocation()
	if type(GetPlayerPawn) ~= "function" then return nil end
	local ok, pawn = pcall(GetPlayerPawn)
	if not ok or not pawn then return nil end
	local locationOk, location = pcall(function() return pawn:K2_GetActorLocation() end)
	return locationOk and location or nil
end

local function UpdateNearbyMeter()
	if ParkingMeter.ActiveMeterId then
		if ParkingMeter.NearbyMeterId then
			local previous = ParkingMeter.Meters[ParkingMeter.NearbyMeterId]
			if previous then SetComponentVisible(previous.components.InteractText, false) end
		end
		ParkingMeter.NearbyMeterId = nil
		return
	end

	local playerLocation = GetPawnLocation()
	if not playerLocation then return end
	local config = Config and Config.ParkingMeter or {}
	local bestId = nil
	local bestDistance = tonumber(config.InteractionDistance) or 180
	for id, meter in pairs(ParkingMeter.Meters) do
		local distance = DistanceBetween(playerLocation, meter.location)
		if distance <= bestDistance then
			bestDistance = distance
			bestId = id
		end
	end

	if ParkingMeter.NearbyMeterId ~= bestId then
		local previous = ParkingMeter.Meters[ParkingMeter.NearbyMeterId or ""]
		if previous then SetComponentVisible(previous.components.InteractText, false) end
		ParkingMeter.NearbyMeterId = bestId
		local current = ParkingMeter.Meters[bestId or ""]
		if current then
			SetText(current.components.InteractText, "PRESS [E] TO USE")
			SetComponentVisible(current.components.InteractText, true)
		end
	end
end

local function PressActiveButton(buttonName)
	local meter = ParkingMeter.Meters[ParkingMeter.ActiveMeterId or ""]
	if not meter then return end
	local component = meter.components[buttonName]
	if not component then return end
	local ok, pressReason = ParkingMeter.PressButton(component, meter)
	if not ok then Log("warn", "Parking meter button failed", { button = buttonName, reason = pressReason }) end
end

function ParkingMeter.SetReservation(id, _, expiresAt)
	local meter = ParkingMeter.Meters[tostring(id or "")]
	if not meter then return false, "meter_not_found" end
	meter.state.expiresAt = tonumber(expiresAt)
	meter.state.confirmed = RemainingSeconds(meter) > 0
	RefreshDisplay(meter)
	return true
end

local function Initialize(attempt)
	attempt = tonumber(attempt) or 1
	local config = Config and Config.ParkingMeter or nil
	if not config or config.Enabled == false then return end
	local index = 0
	for _ in pairs(ParkingMeter.Meters) do index = index + 1 end

	if config.AutoDiscoverPlacedActors == true and UE and UE.UGameplayStatics and UE.UClass then
		local okClass, class = pcall(function() return UE.UClass.Load(config.Blueprint) end)
		if okClass and class then
			local actors = UE.TArray(UE.AActor)
			local okActors = pcall(function() UE.UGameplayStatics.GetAllActorsOfClass(HWorld, class, actors) end)
			if okActors then
				for _, actor in pairs(actors) do
					index = index + 1
					RegisterMeter(actor, { id = "parking_meter_world_" .. index }, index)
				end
			end
		end
	end

	for _, definition in ipairs(type(config.Locations) == "table" and config.Locations or {}) do
		local ok, actor = pcall(SpawnConfiguredMeter, definition)
		if ok and actor then
			index = index + 1
			RegisterMeter(actor, definition, index)
		else
			Log("warn", "Parking meter spawn failed", { id = definition.id, error = tostring(actor) })
		end
	end
	Log("info", "Parking meter runtime initialized", { meters = index, attempt = attempt })
	if index > 0 and Timer and type(Timer.SetInterval) == "function" then
		if not ParkingMeter.ProximityTimer then
			ParkingMeter.ProximityTimer = Timer.SetInterval(UpdateNearbyMeter, PROXIMITY_INTERVAL)
		end
		if not ParkingMeter.DisplayTimer then
			ParkingMeter.DisplayTimer = Timer.SetInterval(function()
				for _, meter in pairs(ParkingMeter.Meters) do RefreshDisplay(meter) end
			end, DISPLAY_INTERVAL)
		end
	end
	if index == 0 and attempt < 10 and Timer and type(Timer.SetTimeout) == "function" then
		Timer.SetTimeout(function() Initialize(attempt + 1) end, 1000)
	end
end

if Input and type(Input.BindKey) == "function" then
	Input.BindKey("E", function()
		if ParkingMeter.ActiveMeterId or not ParkingMeter.NearbyMeterId then return end
		local ok, reason = ParkingMeter.OpenById(ParkingMeter.NearbyMeterId)
		if not ok then Log("warn", "Parking meter open failed", { reason = reason }) end
	end, "Pressed")
	Input.BindKey("One", function() if ParkingMeter.ActiveMeterId then PressActiveButton("Button_1") end end, "Pressed")
	Input.BindKey("Two", function() if ParkingMeter.ActiveMeterId then PressActiveButton("Button_2") end end, "Pressed")
	Input.BindKey("Three", function() if ParkingMeter.ActiveMeterId then PressActiveButton("Button_3") end end, "Pressed")
	Input.BindKey("Four", function() if ParkingMeter.ActiveMeterId then PressActiveButton("Button_4") end end, "Pressed")
	Input.BindKey("BackSpace", function()
		if ParkingMeter.ActiveMeterId then CloseMeter() end
	end, "Pressed")
	Input.BindKey("Escape", function()
		if ParkingMeter.ActiveMeterId then CloseMeter() end
	end, "Pressed")
end

RegisterClientEvent("m-phone:parkingMeter:open", function(data)
	local ok, reason = ParkingMeter.OpenById(type(data) == "table" and data.id or "")
	if not ok then Log("warn", "Parking meter open failed", { reason = reason }) end
end)

RegisterClientEvent("m-phone:parkingMeter:press", function(data)
	local ok, reason = ParkingMeter.PressById(type(data) == "table" and data.id or "", type(data) == "table" and data.button or "")
	if not ok then Log("warn", "Parking meter button failed", { reason = reason }) end
end)

RegisterClientEvent("m-phone:parkingMeter:result", function(data)
	data = type(data) == "table" and data or {}
	local state = type(data.state) == "table" and data.state or nil
	local meterId = state and state.meterId or data.meterId
	local meter = ParkingMeter.Meters[tostring(meterId or ParkingMeter.ActiveMeterId or "")]
	if not meter then return end
	meter.state.pending = false
	if data.ok ~= true then
		local errors = {
			insufficient_funds = "NO FUNDS",
			invalid_duration = "INVALID TIME",
			money_api_unavailable = "UNAVAILABLE",
			inventory_full = "INVENTORY FULL",
			inventory_unavailable = "NO INVENTORY",
			meter_busy = "METER BUSY",
			document_service_unavailable = "RECEIPT OFFLINE",
			document_create_failed = "RECEIPT FAILED",
			document_activation_failed = "RECEIPT FAILED",
			receipt_item_failed = "RECEIPT FAILED",
			refund_failed = "CONTACT SUPPORT",
		}
		meter.state.errorText = errors[data.error] or "PAYMENT FAILED"
		meter.state.paymentText = nil
		Log("warn", "Parking meter server request failed", { error = data.error })
		RefreshDisplay(meter)
		return
	end
	meter.state.expiresAt = tonumber(state.expiresAt)
	meter.state.errorText = nil
	if data.operation == "payment" then
		meter.state.paymentText = data.paymentSource == "cash" and "PAID CASH / RECEIPT" or "PAID BANK / RECEIPT"
		meter.state.minutes = MINUTES_STEP
	else
		meter.state.paymentText = nil
	end
	meter.state.confirmed = state.active == true and RemainingSeconds(meter) > 0
	RefreshDisplay(meter)
end)

if Timer and type(Timer.SetTimeout) == "function" then
	Timer.SetTimeout(function() Initialize(1) end, 1500)
else
	Initialize(1)
end

_G.MPhoneParkingMeter = ParkingMeter
return ParkingMeter
