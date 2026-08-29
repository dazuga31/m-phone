return {
	id = "mphone.template",
	sdkVersion = 1,
	version = "1.0.0",
	label = "Template App",
	description = "SDK reference application for custom HELIX integrations.",
	developer = "m-phone",
	provider = "m-phone",
	icon = "PhoneApps/TemplateApp/web/icon.svg",
	web = {
		entry = "PhoneApps/TemplateApp/web/index.html",
		mode = "sandboxed",
	},
	surfaces = {
		phone = true,
		desktop = true,
		tablet = false,
	},
	installable = true,
	defaultInstalled = true,
	category = "development",
	permissions = { "player.basic", "notifications" },
	order = 850,
}
