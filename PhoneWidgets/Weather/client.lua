local Widget = {}
local function LoadWeather(done)
	local completed = false
	local function finish(payload) if completed then return end; completed = true; done(payload) end
	local ok = pcall(function()
		TriggerCallback("syncRequest", function(info)
			info = type(info) == "table" and info or {}
			finish({ ok = true, weather = tostring(info.weather or "ClearSkies"), time = tonumber(info.time) or 1200, source = "qb-weathersync" })
		end)
	end)
	if not ok then finish({ ok = true, weather = "ClearSkies", time = 1200, source = "fallback" }) end
end
function Widget.HandleRequest(action, _, _, done)
	if action == "open" or action == "refresh" then LoadWeather(done); return nil end
	return { ok = false, error = "unknown_action" }
end
return Widget
