local TabletTemplate = {}

function TabletTemplate.HandleRequest(controller, action, payload, context)
	local surface = tostring(context and context.surface or "")
	if surface ~= "tablet" then
		return { ok = false, error = "tablet_surface_required" }
	end

	if action == "open" then
		return {
			ok = true,
			message = "Tablet App Template connected to m-phone SDK.",
			surface = surface,
		}
	end

	if action == "ping" then
		return {
			ok = true,
			message = tostring(payload and payload.message or "Pong from Tablet Lua"),
			serverTime = os.time(),
			surface = surface,
		}
	end

	return { ok = false, error = "unknown_action" }
end

return TabletTemplate
