local Widget = {}

function Widget.HandleRequest(controller, action, payload, context)
	if action == "serverPing" then
		return {
			ok = true,
			message = tostring(payload and payload.message or "Pong"),
			size = tostring(context and context.size or "minimal"),
			serverTime = os.time(),
		}
	end
	return { ok = false, error = "unknown_action" }
end

return Widget
