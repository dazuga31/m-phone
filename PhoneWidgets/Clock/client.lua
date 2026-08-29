local Widget = {}
function Widget.HandleRequest(action)
	if action == "open" or action == "refresh" then return { ok = true, serverTime = os.time() } end
	return { ok = false, error = "unknown_action" }
end
return Widget
