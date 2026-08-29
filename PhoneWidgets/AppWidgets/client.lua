local Widget = { Handlers = {} }

local defaults = {
	["mphone.activity"] = { eyebrow = "Activity", title = "All caught up", detail = "No new updates" },
	["mphone.trucker"] = { eyebrow = "Trucker", title = "No active route", detail = "Ready for a new haul" },
	["mphone.courier"] = { eyebrow = "Courier", title = "No active delivery", detail = "Ready for a new assignment" },
	["mphone.gallery"] = { eyebrow = "Gallery", title = "Open Gallery", detail = "View your recent captures" },
	["mphone.chat"] = { eyebrow = "Messages", title = "No unread messages", detail = "Open your conversations" },
	["mphone.bank"] = { eyebrow = "Bank", title = "Account available", detail = "Open Bank for live balance" },
	["mphone.parking"] = { eyebrow = "Parking", title = "No active parking", detail = "Open Parking to buy a permit" },
}

for id, payload in pairs(defaults) do
	Widget.Handlers[id] = function(action)
		if action == "open" or action == "refresh" then return { ok = true, widget = payload } end
		return { ok = false, error = "unknown_action" }
	end
end

return Widget
