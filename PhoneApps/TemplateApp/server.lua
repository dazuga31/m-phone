local Template = {}

function Template.HandleRequest(controller, action, payload, context)
	if action == "open" then
		return {
			ok = true,
			message = "Template App connected to m-phone SDK.",
			surface = tostring(context and context.surface or "phone"),
		}
	end

	if action == "ping" then
		return {
			ok = true,
			message = tostring(payload and payload.message or "Pong from Lua"),
			serverTime = os.time(),
		}
	end

	return { ok = false, error = "unknown_action" }
end

return Template
