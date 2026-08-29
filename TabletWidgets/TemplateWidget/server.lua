local Widget = {}

function Widget.HandleRequest(controller, action, payload, context)
	if type(context) ~= "table" or tostring(context.surface or "") ~= "tablet" then
		return { ok = false, error = "tablet_surface_required" }
	end
	if action == "serverPing" then
		return {
			ok = true,
			message = tostring(payload and payload.message or "Pong"),
			size = tostring(context.size or "wide"),
			surface = "tablet",
			serverTime = os.time(),
		}
	end
	return { ok = false, error = "unknown_action" }
end

return Widget
