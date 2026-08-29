-- m-phone/client_shared.lua

local Shared = {}

function Shared.ResolveNotificationType(level)
	if type(NotificationType) ~= "table" then
		return nil
	end

	if level == "error" then
		return NotificationType.Error
	end

	if level == "warn" then
		return NotificationType.Info
	end

	if level == "success" then
		return NotificationType.Success
	end

	return NotificationType.Info
end

function Shared.SafeNotification(text, time, pos, level)
	local duration = math.floor(tonumber(time) or 3)
	if duration < 1 then
		duration = 1
	end

	text = tostring(text or "")

	local ok = false
	local notifType = Shared.ResolveNotificationType(level)

	if notifType ~= nil then
		ok = pcall(function()
			Notification(text, notifType, duration)
		end)
	end

	if not ok then
		ok = pcall(function()
			Notification(text, duration, pos)
		end)
	end

	if not ok then
		print("[m-phone][notify-fallback] " .. text)
	end

	return ok
end

function Shared.Notify(level, msg, tag, extra, duration)
	level = tostring(level or "info")
	tag = tostring(tag or "m-phone")
	msg = tostring(msg or "")

	local text = string.format("[%s][%s] %s", tag, level, msg)

	local t = duration
	if not t then
		if level == "error" then
			t = 4
		elseif level == "warn" then
			t = 3
		elseif level == "debug" then
			t = 2
		elseif level == "success" then
			t = 2
		else
			t = 2
		end
	end

	local pos = nil
	if NotificationPosition and NotificationPosition.TopRight then
		pos = NotificationPosition.TopRight
	end

	if level == "debug" or level == "info" then
		print(text)

		if level == "debug" and extra ~= nil then
			print("[m-phone][debug-extra] " .. tostring(tag), extra)
		end

		return
	end

	Shared.SafeNotification(text, t, pos, level)
end

function Shared.SendToUI(target, eventName, payload)
	if not target then return false end
	local ok = pcall(function()
		target:SendEvent(eventName, payload)
	end)
	return ok
end

function Shared.SendToUIs(hud, ui, eventName, payload)
	Shared.SendToUI(hud, eventName, payload)
	Shared.SendToUI(ui, eventName, payload)
end

function Shared.ResolvePlayerController(hud)
	if _G.MPhoneClient and _G.MPhoneClient.GetPlayerController then
		local ok, pc = pcall(function()
			return _G.MPhoneClient:GetPlayerController()
		end)
		if ok and pc then return pc end
	end

	if hud and hud.GetPlayerController then
		local ok, pc = pcall(function()
			return hud:GetPlayerController()
		end)
		if ok and pc then return pc end
	end

	if _G.PlayerController then
		return _G.PlayerController
	end

	return nil
end

function Shared.TryCall(fn, ...)
	if type(fn) ~= "function" then return false end
	return pcall(fn, ...)
end

return Shared
