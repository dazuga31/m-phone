-- m-phone/config.lua

Config = Config or {}
Config.Use = Config.Use or {}

Config.Use.Core = "qb"               -- qb or m; m-core adapter is reserved for future integration
Config.Use.Bank = "qb"               -- qb or mbank
Config.Inventory = "auto"            -- auto, none, m-inventory, qb-inventory, hl-inventory
Config.LegacyLocalDomainSchema = false

Config.Banking = {
	Provider = Config.Use.Bank,
	Resource = "m-banking",
}

Config.Trucker = {
	Resource = "m-trucker",
}

Config.Desktop = {
	Resource = "m-desktop",
}

Config.Courier = {
	Resource = "m-courier",
	Debug = false,
}

Config.Business = {
	Resource = "m-business",
}

Config.Jobs = {
	Resource = "m-jobs",
}

Config.Communications = {
	PhoneNumberDigits = 6,
	PhoneNumberMetadataKey = "phoneNumber",
	MaxMessageLength = 500,
	MaxContactNameLength = 48,
	MaxContacts = 250,
	MessagePageSize = 40,
	RateLimitWindowSeconds = 10,
	RateLimitMessages = 8,
	CallRingTimeoutSeconds = 30,
	Voice = {
		Enabled = true,
		Provider = "helix",
		ChannelStart = 70000,
		ChannelEnd = 79999,
	},
	SystemContacts = {
		{ id = "system:emergency", name = "Emergency Services", phoneNumber = "911000", category = "emergency" },
		{ id = "system:government", name = "Citizen Services", phoneNumber = "311000", category = "government" },
	},
}

-- Public feature switches. Disabled features do not register their Lua
-- handlers and are removed from Desktop terminal app lists.
Config.Features = {
	Phone = true,
	Desktop = false,
	Tablet = false,
	POS = false,
	Camera = true,
	Gallery = true,
	Bank = true,
	Trucker = false,
	Courier = false,
	Garage = false,
	Parking = true,
	ParkingMeter = false,
	CitizenServices = false,
	PropertyMarket = false,
	FurnitureStore = false,
	ShopManager = false,
	JobCentre = false,
	Rewards = false,
	CreatorLink = false,
}

Config.Dependencies = {
	Required = { "qb-core" },
	Optional = {
		["m-inventory"] = { "CreatorLink", "CitizenServices", "ParkingMeter" },
		["m-banking"] = { "Bank", "Parking", "Rewards", "ParkingMeter" },
		["m-trucker"] = { "Trucker" },
		["m-courier"] = { "Courier" },
		["m-business"] = { "POS", "ShopManager", "FurnitureStore" },
		["m-jobs"] = { "JobCentre" },
		["m-attachments"] = { "Phone" },
		["m-desktop"] = { "CitizenServices" },
		["m-documents"] = { "CitizenServices", "ParkingMeter", "PropertyMarket" },
		["m-markers"] = { "Trucker" },
		["m-properties"] = { "PropertyMarket", "Garage" },
		["m-vehicleshop"] = { "Garage" },
		["hl-jungle"] = { "FurnitureStore" },
	},
}

Config.PhoneUse = {
	Enabled = true,
	Attachment = {
		enabled = false,
		owner = "m-phone",
		slot = "phone",
		mesh = "/MProps/Items/Phone/gltf/StaticMeshes/phone_1.phone_1",
		bone = "hand_r",
		location = Vector(-8.700, -2.100, 0.900),
		rotation = Rotator(-28.000, 158.900, 9.400),
		scale = 1.000,
	},
}

Config.ParkingMeter = {
	Enabled = false,
	MinutesStep = 15,
	PricePerStep = 15,
	DefaultMinutes = 30,
	MaxMinutes = 240,
	Blueprint = "/MProps/Parking/ParkingPayStand/Blueprints/BP_ParkingPayStand.BP_ParkingPayStand_C",
	-- Automatically connects every BP_ParkingPayStand already placed in the world.
	AutoDiscoverPlacedActors = true,
	-- Optional Lua-spawned meters. Each entry accepts id, transform and spatial overrides.
	Locations = {},
	InteractionDistance = 180,
	InteractionUiDistance = 180,
	Spatial = {
		-- Camera-only view. The meter uses its physical buttons: 1 = +15,
		-- 2 = pay, 3 = back, 4 = -15. No viewport cursor is required.
		cameraDistance = 35.0,
		cameraAxis = "right",
		cameraNormalSign = 0.0,
		cameraHeight = 0.0,
		cameraSideOffset = 0.0,
		cameraFov = 45.0,
		cameraSharpen = 1.0,
	},
}

-- Phone Parking App. Prices are stored in cents and calculated exclusively
-- on the server. Zone IDs must stay four digits because players enter the ID
-- printed on the physical parking sign.
Config.ParkingApp = {
	Enabled = true,
	MinutesStep = 15,
	DefaultMinutes = 30,
	MaxMinutes = 480,
	PeakPeriods = {
		{ days = { 2, 3, 4, 5, 6 }, startMinute = 450, endMinute = 570 },
		{ days = { 2, 3, 4, 5, 6 }, startMinute = 960, endMinute = 1110 },
	},
	Zones = {
		["0001"] = { label = "Central Station", district = "City Centre", pricePer15 = 225, weekendDiscount = 20, peakFee = 30, maxMinutes = 240 },
		["0002"] = { label = "Civic Square", district = "City Centre", pricePer15 = 200, weekendDiscount = 20, peakFee = 25, maxMinutes = 240 },
		["0003"] = { label = "Government Quarter", district = "Civic District", pricePer15 = 250, weekendDiscount = 25, peakFee = 30, maxMinutes = 180 },
		["0004"] = { label = "Financial District", district = "Downtown", pricePer15 = 275, weekendDiscount = 20, peakFee = 35, maxMinutes = 180 },
		["0005"] = { label = "Market Street", district = "Downtown", pricePer15 = 175, weekendDiscount = 15, peakFee = 25, maxMinutes = 300 },
		["0006"] = { label = "Old Town", district = "Old Town", pricePer15 = 150, weekendDiscount = 10, peakFee = 20, maxMinutes = 360 },
		["0007"] = { label = "Community Park", district = "North Pacifica", pricePer15 = 0, weekendDiscount = 0, peakFee = 0, maxMinutes = 240, free = true },
		["0008"] = { label = "University East", district = "Education Quarter", pricePer15 = 125, weekendDiscount = 30, peakFee = 15, maxMinutes = 480 },
		["0009"] = { label = "University West", district = "Education Quarter", pricePer15 = 125, weekendDiscount = 30, peakFee = 15, maxMinutes = 480 },
		["0010"] = { label = "General Hospital", district = "Medical Quarter", pricePer15 = 100, weekendDiscount = 25, peakFee = 10, maxMinutes = 480 },
		["0011"] = { label = "Harbour Front", district = "Marina", pricePer15 = 175, weekendDiscount = 10, peakFee = 20, maxMinutes = 360 },
		["0012"] = { label = "Marina South", district = "Marina", pricePer15 = 200, weekendDiscount = 10, peakFee = 20, maxMinutes = 360 },
		["0013"] = { label = "Stadium North", district = "Sports Quarter", pricePer15 = 225, weekendDiscount = 0, peakFee = 15, maxMinutes = 360 },
		["0014"] = { label = "Stadium South", district = "Sports Quarter", pricePer15 = 225, weekendDiscount = 0, peakFee = 15, maxMinutes = 360 },
		["0015"] = { label = "Airport Short Stay", district = "Airport", pricePer15 = 350, weekendDiscount = 0, peakFee = 20, maxMinutes = 180 },
		["0016"] = { label = "Airport Long Stay", district = "Airport", pricePer15 = 125, weekendDiscount = 10, peakFee = 10, maxMinutes = 480 },
		["0017"] = { label = "Industrial Estate", district = "Industrial", pricePer15 = 100, weekendDiscount = 20, peakFee = 10, maxMinutes = 480 },
		["0018"] = { label = "Park and Ride", district = "West Pacifica", pricePer15 = 0, weekendDiscount = 0, peakFee = 0, maxMinutes = 480, free = true },
		["0019"] = { label = "Beach Promenade", district = "Coast", pricePer15 = 175, weekendDiscount = 0, peakFee = 10, maxMinutes = 360 },
		["0020"] = { label = "Pier Parking", district = "Coast", pricePer15 = 200, weekendDiscount = 0, peakFee = 10, maxMinutes = 300 },
		["0021"] = { label = "Museum Quarter", district = "Culture District", pricePer15 = 150, weekendDiscount = 25, peakFee = 15, maxMinutes = 360 },
		["0022"] = { label = "Convention Centre", district = "City Centre", pricePer15 = 250, weekendDiscount = 10, peakFee = 30, maxMinutes = 300 },
		["0023"] = { label = "Riverside", district = "East Pacifica", pricePer15 = 125, weekendDiscount = 20, peakFee = 15, maxMinutes = 480 },
		["0024"] = { label = "North Residential", district = "North Pacifica", pricePer15 = 75, weekendDiscount = 35, peakFee = 10, maxMinutes = 480 },
		["0025"] = { label = "South Residential", district = "South Pacifica", pricePer15 = 75, weekendDiscount = 35, peakFee = 10, maxMinutes = 480 },
		["0026"] = { label = "Shopping Centre", district = "Retail Park", pricePer15 = 100, weekendDiscount = 15, peakFee = 10, maxMinutes = 360 },
		["0027"] = { label = "Freight Terminal", district = "Logistics Park", pricePer15 = 125, weekendDiscount = 20, peakFee = 20, maxMinutes = 480 },
		["0028"] = { label = "Forest Visitor Centre", district = "Countryside", pricePer15 = 50, weekendDiscount = 0, peakFee = 0, maxMinutes = 480 },
		["0029"] = { label = "Public Library", district = "Civic District", pricePer15 = 0, weekendDiscount = 0, peakFee = 0, maxMinutes = 180, free = true },
		["0030"] = { label = "Nightlife District", district = "Downtown", pricePer15 = 250, weekendDiscount = 0, peakFee = 25, maxMinutes = 240 },
	},
}

function Config.IsFeatureEnabled(name)
	if type(Config.Features) ~= "table" then return true end
	return Config.Features[tostring(name or "")] ~= false
end

Config.AppFeatures = {
	["bank.home"] = "Bank",
	["citizen.services"] = "CitizenServices",
	["trucker"] = "Trucker",
	["shop.manager"] = "ShopManager",
	["furniture.store"] = "FurnitureStore",
	["property.market"] = "PropertyMarket",
	["jobcentre"] = "JobCentre",
	["creatorlink"] = "CreatorLink",
}

function Config.FilterAllowedApps(apps)
	local filtered = {}
	for _, appId in ipairs(type(apps) == "table" and apps or {}) do
		local feature = Config.AppFeatures[tostring(appId)]
		if not feature or Config.IsFeatureEnabled(feature) then
			filtered[#filtered + 1] = appId
		end
	end
	return filtered
end
Config.InventoryPriority = { "m-inventory", "qb-inventory", "hl-inventory" }
Config.InventoryItemMap = {
	["qb-inventory"] = {
	},
	["hl-inventory"] = {},
	["m-inventory"] = {},
}

-- Public item-image provider used by the compiled Phone/Desktop WebUI.
-- Keep inventory artwork in the inventory resource instead of duplicating it
-- inside m-phone. Change BaseUrl when integrating another inventory package.
Config.InventoryImages = {
	Provider = "auto",
	AutoFallback = "qb-inventory",
	BaseUrl = "",
	Extension = ".png",
	FallbackUrl = "",
	Overrides = {},
	Providers = {
		["m-inventory"] = {
			BaseUrl = "http://localhost:12890/m-inventory/web/assets/items",
			Extension = ".png",
		},
		["qb-inventory"] = {
			BaseUrl = "http://localhost:12890/qb-inventory/Client/web/dist/images",
			Extension = ".png",
		},
		["hl-inventory"] = {
			BaseUrl = "",
			Extension = ".png",
		},
	},
}

Config.CitizenServices = {
	MaxDistance = 500.0,
	Services = {
		state_id = {
			enabled = true,
			itemId = "state_id",
			feePence = 2500,
			validityDays = 1460,
			issuedBy = "Pacifica Department of State",
			numberPrefix = "PAC",
		},
		driver_license = { enabled = false },
		medical_card = { enabled = false },
		firearms_license = { enabled = false },
	},
}

Config.Camera = {
	CaptureWidth = 720,
	CaptureHeight = 900,
	SelfieExposureBias = 0.8,
	RearExposureBias = 0.0,
	MaxPhotos = 200,
	ServerRequestTimeoutMs = 20000,
	Storage = {
		-- Remote photos render directly inside WebUI on every device.
		-- Copy camera_storage_local.example.lua to camera_storage_local.lua and
		-- configure server-only endpoints and credentials there.
		Mode = "custom",
		LocalDirectory = "MPhone/Photos/",
		Custom = {
			UploadTicketPath = "/api/mphone/photos/upload-ticket",
			DeletePath = "/api/mphone/photos/",
		},
		FiveManage = {
			Url = "https://api.fivemanage.com/api/v3/file",
			PresignedUrl = "https://api.fivemanage.com/api/v3/file/presigned-url",
		},
	},
}

Debug = false

Config.Developer = {
	-- TEST_MAP remains available to all creators, but privileged mutations are
	-- disabled unless the server owner explicitly enables both switches.
	AllowTestMutations = false,
}

Config.SDK = {
	Enabled = true,
	Version = 1,
	RequestTimeoutMs = 10000,
	MaxPayloadDepth = 8,
	MaxPayloadKeys = 256,

	-- App templates are distributed separately. Add their manifests here after
	-- installing the template package or a custom external App resource.
	Apps = {},
}

Config.WidgetSDK = {
	Enabled = true,
	Version = 1,
	Widgets = {
		{ Manifest = "PhoneWidgets.Clock.manifest", Client = "PhoneWidgets.Clock.client" },
		{ Manifest = "PhoneWidgets.Weather.manifest", Client = "PhoneWidgets.Weather.client" },
		{ Manifest = "PhoneWidgets.AppWidgets.activity_manifest", Client = "PhoneWidgets.AppWidgets.client" },
		{ Feature = "Trucker", Manifest = "PhoneWidgets.AppWidgets.trucker_manifest", Client = "PhoneWidgets.AppWidgets.client" },
		{ Feature = "Courier", Manifest = "PhoneWidgets.AppWidgets.courier_manifest", Client = "PhoneWidgets.AppWidgets.client" },
		{ Feature = "Gallery", Manifest = "PhoneWidgets.AppWidgets.gallery_manifest", Client = "PhoneWidgets.AppWidgets.client" },
		{ Manifest = "PhoneWidgets.AppWidgets.chat_manifest", Client = "PhoneWidgets.AppWidgets.client" },
		{ Feature = "Bank", Manifest = "PhoneWidgets.AppWidgets.bank_manifest", Client = "PhoneWidgets.AppWidgets.client" },
		{ Feature = "Parking", Manifest = "PhoneWidgets.AppWidgets.parking_manifest", Client = "PhoneWidgets.AppWidgets.client" },
		{ Feature = "CreatorLink", Manifest = "PhoneWidgets.CreatorLink.support_manifest", Server = "PhoneWidgets.CreatorLink.support_server" },
		{ Feature = "CreatorLink", Manifest = "PhoneWidgets.CreatorLink.pulse_manifest", Server = "PhoneWidgets.CreatorLink.pulse_server" },

		-- External Phone and Tablet Widget templates are distributed separately.
		-- Install a template package, rename its manifest id, and add it here.
	},
}

-- =============================================================================
-- COMMERCE PROFILE: TEST MAP / HELIX STUDIO (ACTIVE)
-- Desktop interactables and document-service coordinates are owned by m-desktop.
-- This profile retains only phone-hosted shop and ATM domain configuration.
-- =============================================================================
Config.ActiveMap = "TEST_MAP" -- PACIFICA_MAP or TEST_MAP


-- VAT
Config.ShopPricesIncludeVAT = false
Config.ShopVATRate = 0.20            -- 20%

-- Shop products
Config.ShopProducts = {
	-- Drinks
	{ id = "caned_water_union_rasperry", name = "Water",       description = "Clean water, thirst refill fast.",   price = 1.25,    category = "Drinks",  image = "caned_water_union_rasperry" },
	{ id = "caned_union_cola",           name = "Cola",        description = "Sweet cola, thirst refill fast..",   price = 1.50,    category = "Drinks",  image = "caned_union_cola" },
	{ id = "grapejuice",                 name = "Grape Juice", description = "Grape juice, thirst refill fast.",   price = 2.25,    category = "Drinks",  image = "grapejuice" },

	-- Food
	{ id = "food_burger",                name = "Burger",      description = "Burger meal, hunger refill fast.",   price = 3.75,    category = "Food",    image = "food_burger" },
	{ id = "fish",                       name = "Fish",        description = "Fresh fish, hunger refill fast..",   price = 2.50,    category = "Food",    image = "fish" },

	-- Utility
	{ id = "lighter",                    name = "Lighter",     description = "Pocket lighter, quick use tool..",   price = 1.00,    category = "Utility", image = "lighter" },

	-- Tools
	{ id = "toolbox",                    name = "Toolbox",     description = "Basic kit for quick field repairs.", price = 60.00,   category = "Tools",   image = "toolbox" },
	{ id = "jerry_can",                  name = "Jerry Can",   description = "Fuel can for refill jobs today...",  price = 35.00,   category = "Tools",   image = "jerry_can" },
	{ id = "laptop",                     name = "Laptop",      description = "Portable PC for work tasks daily.",  price = 1100.00, category = "Tools",   image = "laptop" },

	-- Devices
	{ id = "iphone",                     name = "Phone",       description = "Smartphone for apps and calls..",    price = 750.00,  category = "Devices", image = "iphone" },

	-- Gear
	{ id = "bag_small",                  name = "Backpack",            description = "Small bag, extra carry space..",    price = 120.00,  category = "Gear", image = "bag_small" },
	{ id = "backpack_black",             name = "Backpack Black",      description = "Standard pack, extra carry space.", price = 160.00,  category = "Gear", image = "backpack_black" },
	{ id = "backpack_green",             name = "Backpack Green",      description = "Green pack, extra carry space...",  price = 180.00,  category = "Gear", image = "backpack_green" },
	{ id = "small_backpack",             name = "Small Backpack",      description = "Light pack, extra carry space...",  price = 95.00,   category = "Gear", image = "small_backpack" },
	{ id = "military_backpack_multi1",   name = "Military Backpack",   description = "Military pack, extra carry space.", price = 420.00,  category = "Gear", image = "military_backpack_multi1" },
	{ id = "military_backpack_travel1",  name = "Travel Military Pack",description = "Travel pack, extra carry space..",  price = 480.00,  category = "Gear", image = "military_backpack_travel1" },
	{ id = "military_backpack_desert1",  name = "Desert Military Pack",description = "Desert pack, extra carry space..",  price = 450.00,  category = "Gear", image = "military_backpack_desert1" },
	{ id = "large_backpack",             name = "Large Backpack",      description = "Large pack, extra carry space...",  price = 620.00,  category = "Gear", image = "large_backpack" },

	{ id = "armor",                      name = "Body Armor",          description = "Basic armor, damage reduction..",   price = 650.00,  category = "Gear", image = "armor" },
	{ id = "armor_lspd_5",               name = "LSPD Armor V",        description = "Police armor, damage reduction..",  price = 950.00,  category = "Gear", image = "armor_lspd_5" },
	{ id = "armor_lspd_8",               name = "LSPD Armor VIII",     description = "Police armor, damage reduction...", price = 1450.00, category = "Gear", image = "armor_lspd_8" },
	{ id = "armor_lspd_11",              name = "LSPD Armor XI",       description = "Police armor, damage reduction..",  price = 2200.00, category = "Gear", image = "armor_lspd_11" },
}

Config.ShopLocations = {
	mp_shop = {
		id = "mp_shop",
		label = "MP Shop",
		type = "convenience",
		coords = Vector(870.0, -3045.0, 0.0),
		heading = 90.0,
		products = Config.ShopProducts,
		vatRate = Config.ShopVATRate,
		pricesIncludeVat = Config.ShopPricesIncludeVAT,
		businessPrice = 10,
		deliveryPoint = {
			label = "MP Shop Delivery Zone",
			coords = { x = -354.445511, y = 1329.08136, z = 91.649997 },
			heading = 100.0,
		},
		npc = {
			enabled = true,
			zOffset = 0,
			distance = 300,
			uiDistance = 200,
			marker = { type = "cylinder", offset = { z = -150 }, forward = 200 },
		},
		owned = {
			enabled = true,
		},
	},
	shop_247 = {
		id = "shop_247",
		label = "24/7 Shop",
		type = "convenience",
		coords = Vector(-343.196184, 282.396116, 50.0),
		heading = 90.0,
		products = Config.ShopProducts,
		vatRate = Config.ShopVATRate,
		pricesIncludeVat = Config.ShopPricesIncludeVAT,
		businessPrice = 10,
		deliveryPoint = {
			label = "24/7 Shop Delivery Zone",
			coords = { x = -746.99978, y = 1320.104515, z = 91.649997 },
			heading = 100.0,
		},
		npc = {
			enabled = true,
			zOffset = 0,
			distance = 300,
			uiDistance = 200,
			marker = { type = "cylinder", offset = { z = -150 }, forward = 200 },
		},
		owned = {
			enabled = true,
		},
	},
}


Config.ATMs = {
	atm_full_1 = {
		id = "atm_full_1",
		label = "Full Service ATM",
		canDeposit = true,
		feeRate = 0.03,
	},
	atm_withdraw_1 = {
		id = "atm_withdraw_1",
		label = "Cash Withdrawal ATM",
		canDeposit = false,
		feeRate = 0.03,
	},
	atm_withdraw_2 = {
		id = "atm_withdraw_2",
		label = "Cash Withdrawal ATM",
		canDeposit = false,
		feeRate = 0.03,
	},
}


local TestCommerceMapProfile = {
	ShopLocations = Config.ShopLocations,
	ATMs = Config.ATMs,
}

-- =============================================================================
-- COMMERCE PROFILE: PACIFICA MAP (PRODUCTION)
-- Change Config.ActiveMap above to "PACIFICA_MAP" to activate this section.
-- Shop delivery zones are intentionally left unset until their parking
-- coordinates are measured; ShopManager will temporarily fall back to shop coords.
-- =============================================================================


local function PacificaShop(id, label, x, y, z, heading)
	return {
		id = id,
		label = label,
		type = "convenience",
		coords = Vector(x, y, z),
		heading = heading or 0.0,
		products = Config.ShopProducts,
		vatRate = Config.ShopVATRate,
		pricesIncludeVat = Config.ShopPricesIncludeVAT,
		businessPrice = 10,
		npc = {
			enabled = true,
			zOffset = 0,
			distance = 300,
			uiDistance = 200,
			marker = { type = "cylinder", offset = { z = -150 }, forward = 200 },
		},
		owned = { enabled = true },
	}
end


local PacificaShops = {
	pacifica_shop_1 = PacificaShop("pacifica_shop_1", "Pacifica Shop 1", 563580.0, 561840.0, 4610.0, -90.0),
	pacifica_shop_2 = PacificaShop("pacifica_shop_2", "Pacifica Shop 2", 575130.0, 527510.0, 4572.428, -90.0),
	pacifica_shop_3 = PacificaShop("pacifica_shop_3", "Pacifica Shop 3", 573980.0, 523750.0, 4490.0, -90.0),
	pacifica_shop_4 = PacificaShop("pacifica_shop_4", "Pacifica Shop 4", 574070.0, 522000.0, 4490.0, 0.0),
	pacifica_shop_5 = PacificaShop("pacifica_shop_5", "Pacifica Shop 5", 571180.0, 459620.0, 4480.0, 0.0),
}


local PacificaAtms = {
	pacifica_atm_withdraw_1 = { id = "pacifica_atm_withdraw_1", label = "Cash Withdrawal ATM", canDeposit = false, feeRate = 0.03 },
	pacifica_atm_withdraw_2 = { id = "pacifica_atm_withdraw_2", label = "Cash Withdrawal ATM", canDeposit = false, feeRate = 0.03 },
	pacifica_atm_withdraw_3 = { id = "pacifica_atm_withdraw_3", label = "Cash Withdrawal ATM", canDeposit = false, feeRate = 0.03 },
	pacifica_atm_withdraw_4 = { id = "pacifica_atm_withdraw_4", label = "Cash Withdrawal ATM", canDeposit = false, feeRate = 0.03 },
	pacifica_atm_full_1 = { id = "pacifica_atm_full_1", label = "Full Service ATM", canDeposit = true, feeRate = 0.03 },
	pacifica_atm_full_2 = { id = "pacifica_atm_full_2", label = "Full Service ATM", canDeposit = true, feeRate = 0.03 },
	pacifica_atm_full_terminal_1 = { id = "pacifica_atm_full_terminal_1", label = "Full Service ATM", canDeposit = true, feeRate = 0.03 },
	pacifica_atm_full_terminal_2 = { id = "pacifica_atm_full_terminal_2", label = "Full Service ATM", canDeposit = true, feeRate = 0.03 },
	pacifica_atm_full_terminal_3 = { id = "pacifica_atm_full_terminal_3", label = "Full Service ATM", canDeposit = true, feeRate = 0.03 },
}


Config.CommerceMapProfiles = {
	TEST_MAP = TestCommerceMapProfile,
	PACIFICA_MAP = {
		ShopLocations = PacificaShops,
		ATMs = PacificaAtms,
	},
}

local ActiveCommerceProfile = Config.CommerceMapProfiles[Config.ActiveMap]
if not ActiveCommerceProfile then
	error("[m-phone] Unknown Config.ActiveMap: " .. tostring(Config.ActiveMap))
end

Config.ShopLocations = ActiveCommerceProfile.ShopLocations
Config.ATMs = ActiveCommerceProfile.ATMs
