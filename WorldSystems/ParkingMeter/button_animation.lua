local ButtonAnimation = {}

local ACTIVE = {}
local RELEASED_LOCATIONS = {}
-- FBX button meshes keep their source-model scale and baked positions.
-- Their shallow axis is local Y (bounds depth ~= 0.20), so a physical press
-- moves inward by 0.0669 along -Y. Moving +Z lifts the whole button upward.
local PRESS_DEPTH = 0.0669
local DEFAULT_DURATION_MS = 150
local PRESS_DURATION_MS = 45
local HOLD_DURATION_MS = 20
local STEP_MS = 10

local function Number(value, fallback)
	value = tonumber(value)
	if value == nil then return fallback end
	return value
end

local function GetRelativeLocation(component)
	local ok, location = pcall(function()
		if component.K2_GetRelativeLocation then return component:K2_GetRelativeLocation() end
		if component.GetRelativeLocation then return component:GetRelativeLocation() end
		return component.RelativeLocation
	end)
	if not ok or not location then return nil end
	return Vector(Number(location.X, 0), Number(location.Y, 0), Number(location.Z, 0))
end

local function SetRelativeLocation(component, location)
	return pcall(function()
		if component.K2_SetRelativeLocation then
			component:K2_SetRelativeLocation(location, false, nil, false)
		elseif component.SetRelativeLocation then
			component:SetRelativeLocation(location, false, nil, false)
		else
			component.RelativeLocation = location
		end
	end)
end

local function EaseOut(value)
	return 1 - (1 - value) * (1 - value)
end

local function EaseInOut(value)
	return value < 0.5 and 2 * value * value or 1 - ((-2 * value + 2) ^ 2) / 2
end

function ButtonAnimation.Press(component, options)
	if not component then return false, "missing_component" end
	if not Timer or type(Timer.SetInterval) ~= "function" then return false, "timer_api_unavailable" end

	local key = tostring(component)
	if ACTIVE[key] then return false, "already_animating" end
	local released = RELEASED_LOCATIONS[key] or GetRelativeLocation(component)
	if not released then return false, "relative_location_unavailable" end
	RELEASED_LOCATIONS[key] = Vector(released.X, released.Y, released.Z)

	options = type(options) == "table" and options or {}
	local duration = math.max(60, Number(options.durationMs, DEFAULT_DURATION_MS))
	local delta = math.abs(Number(options.depth, PRESS_DEPTH))
	local pressDuration = math.min(PRESS_DURATION_MS, duration * 0.4)
	local holdDuration = math.min(HOLD_DURATION_MS, duration * 0.2)
	local releaseDuration = math.max(STEP_MS, duration - pressDuration - holdDuration)
	local elapsed = 0
	local timer
	ACTIVE[key] = true

	timer = Timer.SetInterval(function()
		elapsed = elapsed + STEP_MS
		local offset
		if elapsed <= pressDuration then
			offset = delta * EaseOut(elapsed / pressDuration)
		elseif elapsed <= pressDuration + holdDuration then
			offset = delta
		else
			local releaseProgress = math.min(1, (elapsed - pressDuration - holdDuration) / releaseDuration)
			offset = delta * (1 - EaseInOut(releaseProgress))
		end
		SetRelativeLocation(component, Vector(released.X, released.Y - offset, released.Z))

		if elapsed >= duration then
			pcall(function() Timer.ClearInterval(timer) end)
			SetRelativeLocation(component, released)
			ACTIVE[key] = nil
			if type(options.onComplete) == "function" then pcall(options.onComplete) end
		end
	end, STEP_MS)

	return true
end

return ButtonAnimation
