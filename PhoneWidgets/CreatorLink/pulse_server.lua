local CreatorLink = require("PhoneApps.CreatorLink.server")

return {
	HandleRequest = function(controller, action, payload, context)
		return CreatorLink.HandleWidgetRequest("mphone.creatorlink-pulse", controller, action, payload, context)
	end,
}
