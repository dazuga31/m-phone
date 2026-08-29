return {
	id = "mphone.weather", sdkVersion = 1, version = "1.0.0",
	label = "Weather", description = "Current world weather powered by qb-weathersync.", developer = "m-phone", provider = "m-phone",
	web = { entry = "PhoneWidgets/Weather/web/index.html" },
	sizes = { "minimal", "medium", "wide" }, defaultSize = "medium", defaultEnabled = true,
	permissions = { "world.weather" }, order = 20,
}
