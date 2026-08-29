local Settings = require("PhoneWidgets.TemplateWidget.config")
local Widget = {}

function Widget.HandleRequest(action, payload)
	if action == "open" or action == "refresh" then
		return {
			ok = true,
			title = "Widget connected",
			value = tostring(payload and payload.value or "HELIX"),
			accent = Settings.Accent,
			refreshSeconds = Settings.RefreshSeconds,
		}
	end
	if action == "serverPing" then return { forwardToServer = true } end
	return { ok = false, error = "unknown_action" }
end

return Widget
