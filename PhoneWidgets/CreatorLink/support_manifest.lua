return {
	id = "mphone.creatorlink-support", sdkVersion = 1, version = "0.3.0",
	label = "Support Link", description = "Active creator code and reward cycle.",
	developer = "M Development", provider = "m-phone",
	web = { entry = "PhoneWidgets/AppWidgets/web/index.html" },
	sizes = { "minimal", "medium", "wide" }, defaultSize = "medium", defaultEnabled = false,
	permissions = { "player.basic", "creatorlink.profile" }, order = 100,
}
