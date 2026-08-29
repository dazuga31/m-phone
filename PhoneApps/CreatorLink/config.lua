local CreatorConfig = {}

CreatorConfig.Debug = false
CreatorConfig.Core = "qb"
CreatorConfig.DatabaseProvider = "qb-core"

CreatorConfig.InventoryRewards = {
	Enabled = true,
	-- CreatorLink item rewards use m-inventory's transactional item API.
	-- Cash-only rewards continue to work when this resource is unavailable.
	Provider = "m-inventory",
	ContainerId = "player",
}

CreatorConfig.FutureIntegrations = {
	DonateShop = "TODO: connect the future server-owned Donate Shop checkout service.",
	LixPurchases = "TODO: call RecordCreatorLinkTransaction only from the future authoritative LIX purchase API.",
	PremiumPackages = "TODO: replace entitlement placeholders when premium packages are implemented.",
	AdminPanel = "TODO: manage creators, reviews and payouts from a future standalone admin resource.",
}

CreatorConfig.Tests = {
	-- Enable only in a development world to run the pure Lua CreatorLink test suite at startup.
	RunOnStartup = false,
}

CreatorConfig.Finance = {
	-- Players spend LIX on the server. HELIX keeps its platform fee first,
	-- then the creator rate is applied to the server owner's net LIX revenue.
	Currency = "LIX",
	Symbol = "Ⱡ",
	HelixPlatformFeeBps = 3000,
	CommissionBase = "server_net",
}

CreatorConfig.PremiumCurrency = {
	Code = "LIX",
	Symbol = "Ⱡ",
}

CreatorConfig.Startup = {
	MaximumAttempts = 60,
	RetryDelayMs = 1000,
}

CreatorConfig.Attribution = {
	DurationDays = 30,
	InputCooldownSeconds = 2,
	MaximumFailedAttempts = 8,
	FailedAttemptWindowSeconds = 300,
}

CreatorConfig.Rewards = {
	First = {
		Cash = 25000,
		PremiumDays = 7,
		ShopDiscountBps = 1000,
		ShopDiscountDays = 7,
		Items = {
			-- { ItemId = "food_burger", Label = "Burger", Quantity = 20 },
			-- { ItemId = "caned_union_cola", Label = "Cola", Quantity = 20 },
		},
	},
	Repeat = {
		Cash = 10000,
		PremiumDays = 3,
		ShopDiscountBps = 1000,
		ShopDiscountDays = 3,
		Items = {
			-- { ItemId = "food_burger", Label = "Burger", Quantity = 5 },
		},
	},
}

CreatorConfig.PartnerProgress = {
	FirstActivation = { Reputation = 25, Credits = 100, Momentum = 40 },
	RepeatActivation = { Reputation = 10, Credits = 45, Momentum = 20 },
	TransactionSettled = { Reputation = 1, Credits = 5, Momentum = 3 },
	Levels = {
		{ Id = 1, Label = "Rising Creator", Reputation = 0 },
		{ Id = 2, Label = "Verified Creator", Reputation = 500 },
		{ Id = 3, Label = "Official Partner", Reputation = 2000 },
		{ Id = 4, Label = "Featured Partner", Reputation = 6000 },
		{ Id = 5, Label = "Ambassador", Reputation = 15000 },
	},
}

CreatorConfig.PartnerBenefits = {
	{
		Id = "campaign_funds",
		Label = "Campaign Funds",
		Description = "Request virtual funds for an approved creator campaign.",
		Category = "campaign",
		MinimumLevel = 1,
		CostCredits = 500,
		Enabled = true,
	},
	{
		Id = "recording_support",
		Label = "Recording Support",
		Description = "Reserve a staff-assisted recording or livestream session.",
		Category = "production",
		MinimumLevel = 2,
		CostCredits = 750,
		Enabled = true,
	},
	{
		Id = "community_giveaway",
		Label = "Community Giveaway",
		Description = "Request an approved giveaway with server-backed prizes.",
		Category = "community",
		MinimumLevel = 2,
		CostCredits = 1500,
		Enabled = true,
	},
	{
		Id = "creator_merch",
		Label = "Creator Merchandise",
		Description = "Request a branded clothing or collectible production slot.",
		Category = "merchandise",
		MinimumLevel = 3,
		CostCredits = 2200,
		Enabled = true,
	},
	{
		Id = "featured_billboard",
		Label = "Featured Billboard",
		Description = "Submit a channel campaign for an in-world billboard placement.",
		Category = "promotion",
		MinimumLevel = 3,
		CostCredits = 3000,
		Enabled = true,
	},
	{
		Id = "creator_furniture",
		Label = "Creator Furniture",
		Description = "Request an exclusive creator-themed property item.",
		Category = "property",
		MinimumLevel = 3,
		CostCredits = 2400,
		Enabled = true,
	},
	{
		Id = "garage_expansion",
		Label = "Garage Expansion",
		Description = "Request an additional residential vehicle slot.",
		Category = "property",
		MinimumLevel = 4,
		CostCredits = 5000,
		Enabled = true,
	},
	{
		Id = "signature_vehicle",
		Label = "Signature Vehicle",
		Description = "Submit a one-time request for an approved creator vehicle.",
		Category = "exclusive",
		MinimumLevel = 5,
		CostCredits = 12000,
		Enabled = true,
	},
}

CreatorConfig.Partners = {
	{
		Id = "belik",
		Code = "BELIK",
		DisplayName = "BELIK",
		Channel = "Featured creator",
		Description = "Gameplay, guides and community events.",
		OwnerAccountId = "",
		CommissionBps = 500,
		Status = "active",
		Featured = true,
	},
}

CreatorConfig.App = {
	-- Keep true while testing. Set false when CreatorLink should be installed only through your premium flow.
	DefaultInstalled = true,
	Order = 365,
}

CreatorConfig.Widgets = {
	PlayerDefaultEnabled = false,
	PartnerDefaultEnabled = false,
}

CreatorConfig.Applications = {
	Enabled = true,
	MinimumAudience = 100,
	CooldownDays = 14,
	DefaultCommissionBps = 500,
	Platforms = { "YouTube", "TikTok", "Twitch", "Kick", "Instagram", "Other" },
}

return CreatorConfig
