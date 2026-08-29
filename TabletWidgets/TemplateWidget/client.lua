local Settings = require("TabletWidgets.TemplateWidget.config")
local Widget = {}

local function IsTablet(context)
	return type(context) == "table" and tostring(context.surface or "") == "tablet"
end

function Widget.HandleRequest(action, payload, context)
	if not IsTablet(context) then return { ok = false, error = "tablet_surface_required" } end
	if action == "open" or action == "refresh" then
		return {
			ok = true,
			title = "Tablet widget connected",
			value = tostring(payload and payload.value or "HELIX Tablet"),
			accent = Settings.Accent,
			refreshSeconds = Settings.RefreshSeconds,
			surface = "tablet",
		}
	end
	if action == "serverPing" then return { forwardToServer = true } end
	return { ok = false, error = "unknown_action" }
end

return Widget
