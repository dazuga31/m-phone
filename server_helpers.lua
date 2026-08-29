-- m-phone/server_helpers.lua

local Shared = {}
local DB = require("db")

local function FeatureEnabled(name)
	return not Config or not Config.IsFeatureEnabled or Config.IsFeatureEnabled(name)
end

local function AnyFeature(...)
	for index = 1, select("#", ...) do
		if FeatureEnabled(select(index, ...)) then return true end
	end
	return false
end

local function BusinessApi()
	if not AnyFeature("POS", "ShopManager", "FurnitureStore") then return nil end
	return (_G.MPhone and _G.MPhone.Business) or nil
end

local function toNumber(value, fallback)
	return tonumber(value) or fallback or 0
end

local function toString(value, fallback)
	local s = tostring(value or "")
	return s ~= "" and s or tostring(fallback or "")
end

function Shared.GetShopLocation(shopId)
	local id = tostring(shopId or "default")

	if id ~= "default" and Config and type(Config.ShopLocations) == "table" then
		local shop = Config.ShopLocations[id]
		if type(shop) == "table" then
			return shop, id
		end
	end

	return {
		id = "default",
		label = "Shop",
		type = "default",
		products = (Config and Config.ShopProducts) or {},
		vatRate = (Config and Config.ShopVATRate) or 0.2,
		pricesIncludeVat = (Config and Config.ShopPricesIncludeVAT) == true,
	}, "default"
end

function Shared.BuildShopPayload(shopId)
	local shop, resolvedId = Shared.GetShopLocation(shopId)
	local products = shop.products or ((Config and Config.ShopProducts) or {})
	local shopRow = nil
	local ownerId = nil
	local ownerName = ""
	local isOwned = false
	local balance = 0
	local todaySales = 0
	local coords = ""	
	local businessPrice = toNumber(shop.businessPrice or shop.price or 0)
	local status = tostring(shop.status or "setup")

	local business = BusinessApi()
	if business and business.GetShop and resolvedId ~= "default" then
		shopRow = business.GetShop(resolvedId)
		local managed = business.ListManagedShops and business.ListManagedShops() or {}
		local dbProducts = nil
		for _, managedShop in ipairs(managed) do
			if tostring(managedShop.id or "") == resolvedId then
				dbProducts = managedShop.products
				break
			end
		end
		ownerId = shopRow and DB.RowGet(shopRow, "OwnerID") or nil
		isOwned = ownerId ~= nil and tostring(ownerId) ~= ""

		if shopRow then
			balance = toNumber(DB.RowGet(shopRow, "Balance"))
			todaySales = toNumber(DB.RowGet(shopRow, "TodaySales"))
			coords = tostring(DB.RowGet(shopRow, "Coords") or "")
			businessPrice = toNumber(DB.RowGet(shopRow, "BusinessPrice")) / 100
			status = tostring(DB.RowGet(shopRow, "Status") or status)
		end

		if isOwned and DB.GetPlayer then
			local ownerRow = DB.GetPlayer(ownerId)
			ownerName = tostring(ownerRow and DB.RowGet(ownerRow, "Name") or "")
		end

		if type(dbProducts) == "table" and #dbProducts > 0 then
			if not isOwned then
				for _, product in ipairs(dbProducts) do
					product.stock = product.maxStock
				end
			end
			products = dbProducts
		end
	end

	local vat = toNumber(shop.vatRate or (Config and Config.ShopVATRate))
	local pricesIncludeVat = shop.pricesIncludeVat
	if pricesIncludeVat == nil then
		pricesIncludeVat = (Config and Config.ShopPricesIncludeVAT) == true
	else
		pricesIncludeVat = pricesIncludeVat == true
	end

	return {
		meta = {
			id = tostring(shop.id or resolvedId),
			label = tostring(shop.label or resolvedId),
			type = tostring(shop.type or "default"),
			status = status,
			ownerId = ownerId,
			ownerName = ownerName,
			balance = balance / 100,
			todaySales = todaySales / 100,
			coords = coords ~= "" and coords or tostring(shop.coords or ""),
			forSale = not isOwned,
			businessPrice = businessPrice,
			owned = isOwned,
		},
		products = products,
		vat = vat,
		pricesIncludeVat = pricesIncludeVat,
	}
end

function Shared.BuildManagedShopsPayload()
	local business = BusinessApi()
	if business and business.ListManagedShops then
		local managed = business.ListManagedShops()
		if type(managed) == "table" and #managed > 0 then
			return managed
		end
	end

	local list = {}
	local locations = (Config and type(Config.ShopLocations) == "table") and Config.ShopLocations or {}

	for id, shop in pairs(locations) do
		if type(shop) == "table" then
			local products = {}
			for _, product in ipairs(shop.products or {}) do
				local maxStock = toNumber(product.maxStock, 100)
				products[#products + 1] = {
					id = tostring(product.id or product.name or ""),
					label = tostring(product.name or product.label or product.id or "Item"),
					category = tostring(product.category or "General"),
					price = toNumber(product.price),
					stock = toNumber(product.stock or product.defaultStock, maxStock),
					maxStock = maxStock,
					maxOrderQty = toNumber(product.maxOrderQty, math.min(maxStock, 25)),
					enabled = product.enabled == false and false or true,
				}
			end

			local ownerId = shop.ownerId or shop.ownerID or shop.owner
			local isOwned = ownerId ~= nil and tostring(ownerId) ~= ""
			if not isOwned then
				for _, product in ipairs(products) do
					product.stock = product.maxStock
				end
			end

			list[#list + 1] = {
				id = tostring(shop.id or id),
				label = tostring(shop.label or id),
				type = tostring(shop.type or "default"),
				status = tostring(shop.status or "setup"),
				ownerId = ownerId,
				owned = isOwned,
				coords = shop.coords and tostring(shop.coords) or "",
				balance = toNumber(shop.balance),
				todaySales = toNumber(shop.todaySales),
				stockValue = toNumber(shop.stockValue),
				products = products,
			}
		end
	end

	table.sort(list, function(a, b)
		return tostring(a.label or a.id) < tostring(b.label or b.id)
	end)

	return list
end

function Shared.ResolveTruckerApi()
	if Config and Config.IsFeatureEnabled and not Config.IsFeatureEnabled("Trucker") then return {} end
	local core = _G.MPhone or {}
	local trucker = core.Trucker or {}

	return {
		ensureProfile = trucker.EnsureProfileForPlayer,
		getOrders = trucker.GetOrdersForPlayer,
		getProfile = trucker.GetProfileForPlayer,
		getActiveRoute = trucker.GetActiveRouteForPlayer,
	}
end

local function NormalizeInventoryProvider(provider)
	provider = tostring(provider or ""):lower()
	if provider == "m" or provider == "m_inventory" then return "m-inventory" end
	if provider == "qb" or provider == "qb_inventory" then return "qb-inventory" end
	if provider == "hl" or provider == "hl_inventory" then return "hl-inventory" end
	if provider == "disabled" or provider == "off" or provider == "" then return "none" end
	return provider
end

function Shared.ResolveInventoryImages()
	local imageConfig = Config and Config.InventoryImages or {}
	local configuredProvider = imageConfig.Provider
	if configuredProvider == nil or tostring(configuredProvider) == "" then
		configuredProvider = Config and Config.Inventory or "auto"
	end
	local provider = NormalizeInventoryProvider(configuredProvider)
	local resolution = "explicit"
	if provider == "auto" then
		if type(_G.MInventory) == "table" then
			provider = "m-inventory"
			resolution = "runtime-marker"
		else
			provider = NormalizeInventoryProvider(imageConfig.AutoFallback or "qb-inventory")
			resolution = "configured-fallback"
		end
	end
	local providerConfig = type(imageConfig.Providers) == "table" and imageConfig.Providers[provider] or nil
	providerConfig = type(providerConfig) == "table" and providerConfig or {}
	local baseUrl = tostring(imageConfig.BaseUrl or "")
	if baseUrl == "" then baseUrl = tostring(providerConfig.BaseUrl or "") end
	local extension = tostring(imageConfig.Extension or "")
	if extension == "" then extension = tostring(providerConfig.Extension or ".png") end
	return {
		provider = provider ~= "auto" and provider or "none",
		resolution = resolution,
		baseUrl = baseUrl,
		extension = extension ~= "" and extension or ".png",
		fallbackUrl = tostring(imageConfig.FallbackUrl or ""),
		overrides = type(imageConfig.Overrides) == "table" and imageConfig.Overrides or {},
	}
end

function Shared.GetTruckerData(pid, logger, depotId)
	local api = Shared.ResolveTruckerApi()
	local orders = {}
	local profile = nil
	local activeRoutes = {}

	if api.ensureProfile then
		local okEnsure, errEnsure = pcall(function()
			return api.ensureProfile(pid)
		end)

		if not okEnsure and logger and logger.warn then
			logger.warn("EnsureTruckerProfile failed", {
				pid = pid,
				error = tostring(errEnsure)
			})
		end
	end

	if api.getProfile then
		local okProfile, resultProfile = pcall(function()
			return api.getProfile(pid)
		end)

		if okProfile then
			profile = resultProfile
		elseif logger and logger.warn then
			logger.warn("GetTruckerProfileForPlayer failed", {
				pid = pid,
				error = tostring(resultProfile)
			})
		end
	elseif logger and logger.warn then
		logger.warn("GetTruckerProfileForPlayer missing", { pid = pid })
	end

	if api.getOrders then
		local okOrders, resultOrders = pcall(function()
			return api.getOrders(pid, 50, depotId)
		end)

		if okOrders and type(resultOrders) == "table" then
			orders = resultOrders
		elseif logger and logger.warn then
			logger.warn("GetTruckerOrdersForPlayer failed", {
				pid = pid,
				error = tostring(resultOrders)
			})
		end
	elseif logger and logger.warn then
		logger.warn("GetTruckerOrdersForPlayer missing", { pid = pid })
	end

	if api.getActiveRoute then
		local okActive, resultActive = pcall(function()
			return api.getActiveRoute(pid)
		end)

		if okActive and type(resultActive) == "table" and next(resultActive) ~= nil then
			activeRoutes = { resultActive }
		elseif logger and logger.warn then
			logger.warn("GetTruckerActiveRouteForPlayer failed", {
				pid = pid,
				error = tostring(resultActive)
			})
		end
	elseif logger and logger.warn then
		logger.warn("GetTruckerActiveRouteForPlayer missing", { pid = pid })
	end

	return orders, profile, activeRoutes
end

local function GetQBPlayerSnapshot(controller)
	if not controller or not exports or not exports["qb-core"] then
		return nil
	end

	local ok, player = pcall(function()
		return exports["qb-core"]:GetPlayer(controller)
	end)
	if not ok or type(player) ~= "table" or type(player.PlayerData) ~= "table" then
		return nil
	end

	local playerData = player.PlayerData
	local charinfo = type(playerData.charinfo) == "table" and playerData.charinfo or {}
	local firstName = toString(charinfo.firstname or playerData.firstname)
	local lastName = toString(charinfo.lastname or playerData.lastname)
	local fullName = (firstName .. " " .. lastName):match("^%s*(.-)%s*$")
	local money = type(playerData.money) == "table" and playerData.money or {}

	return {
		name = fullName ~= "" and fullName or nil,
		cash = tonumber(money.cash),
	}
end

function Shared.EnsurePlayerRow(pid, controller, logger)
	local row = DB.GetPlayer(pid)
	local snapshot = GetQBPlayerSnapshot(controller)
	local currentName = row and toString(DB.RowGet(row, "Name")) or ""
	local resolvedName = snapshot and snapshot.name or currentName

	if resolvedName == "" then
		resolvedName = "Unknown"
	end

	local shouldUpsert = row == nil or (snapshot and snapshot.name and snapshot.name ~= currentName)
	local initialCash = row and nil or (snapshot and snapshot.cash or 1000)
	local ok = true
	if shouldUpsert then
		ok = DB.UpsertPlayer(pid, resolvedName, initialCash)
	end
	if not ok and logger and logger.error then
		logger.error("DB.UpsertPlayer failed", { pid = pid })
	end

	row = DB.GetPlayer(pid) or row
	if row then
		return row, snapshot
	end

	return {
		ID = pid,
		Name = resolvedName,
		Cash = snapshot and snapshot.cash or 1000,
	}, snapshot
end

function Shared.BuildPhoneMeta(pid)
	local s = DB.GetSettings(pid)
	if not s then
		return {
			settings = {
				language = "en",
				deviceName = "Union Device",
				silentMode = false,
				vibration = true,
				doNotDisturb = false,
				allowFavoriteCalls = true,
				missedCallNotifications = true,
				ui = {
					frameScale = 1.0,
					editMode = false,
					offsetX = 0.0,
					offsetY = 0.0,
				},
			},
			security = {
				setupCompleted = false,
				pinEnabled = false,
				pin = nil,
				faceIdEnabled = false,
			},
		}
	end

	return {
		settings = {
			language = s.language or "en",
			deviceName = s.deviceName or "Union Device",
			silentMode = s.silentMode == true,
			vibration = s.vibration ~= false,
			doNotDisturb = s.doNotDisturb == true,
			allowFavoriteCalls = s.allowFavoriteCalls ~= false,
			missedCallNotifications = s.missedCallNotifications ~= false,
			homeLayout = s.homeLayout,
			tabletLayout = s.tabletLayout,
			ui = s.ui or {
				frameScale = 1.0,
				editMode = false,
				offsetX = 0.0,
				offsetY = 0.0,
			},
		},
		security = {
			setupCompleted = s.setupCompleted == true,
			pinEnabled = s.pinEnabled == true,
			pin = s.pinCode,
			faceIdEnabled = s.faceIdEnabled == true,
		},
	}
end

function Shared.PushFullPayload(controller, pid, requestData, logger)
	if DB and DB.Init then
		DB.Init()
	end

	local row, playerSnapshot = Shared.EnsurePlayerRow(pid, controller, logger)
	requestData = type(requestData) == "table" and requestData or {}
	local shopPayload = { meta = {}, products = {}, vat = 0, pricesIncludeVat = false }
	if AnyFeature("POS", "ShopManager", "FurnitureStore") then
		shopPayload = Shared.BuildShopPayload(requestData.shopId)
	end
	local meta = Shared.BuildPhoneMeta(pid)
	local bankProfile = nil
	if FeatureEnabled("Bank") then
		local banking = _G.MPhone and _G.MPhone.Banking or nil
		if banking and type(banking.GetAccountByPlayerId) == "function" then
			local okBank, result = pcall(banking.GetAccountByPlayerId, pid)
			if okBank then bankProfile = result end
		end
	end

	local desktopContext = type(requestData.desktopContext) == "table" and requestData.desktopContext or requestData
	local depotId = tostring(desktopContext.depotId or "")
	local truckerOrders, truckerProfile, truckerActiveRoutes = {}, nil, {}
	if FeatureEnabled("Trucker") then
		truckerOrders, truckerProfile, truckerActiveRoutes = Shared.GetTruckerData(pid, logger, depotId)
	end
	local inventoryImages = Shared.ResolveInventoryImages()

	local payload = {
		desktopContext = desktopContext,
		runtimeConfig = {
			features = Config.Features or {},
		},
		assetConfig = {
			inventoryImages = inventoryImages,
		},
		player = {
			id = tostring(DB.RowGet(row, "ID") or pid),
			name = tostring((playerSnapshot and playerSnapshot.name) or DB.RowGet(row, "Name") or "Unknown"),
			money = playerSnapshot and playerSnapshot.cash or toNumber(DB.RowGet(row, "Cash")),
		},
		meta = meta,
		shopMeta = shopPayload.meta,
		shopProducts = shopPayload.products,
		shopVatRate = shopPayload.vat,
		shopPricesIncludeVat = shopPayload.pricesIncludeVat,
		bankAccount = {
			hasAccount = bankProfile ~= nil,
		},
		managedShops = FeatureEnabled("ShopManager") and Shared.BuildManagedShopsPayload() or {},
		truckerOrders = truckerOrders,
		truckerProfile = truckerProfile,
		truckerActiveRoutes = truckerActiveRoutes,
	}

	if Debug == true and logger and logger.info then
		logger.info("PHONE META (server)", meta)
		logger.info("TRUCKER PAYLOAD DEBUG", {
			orders = #truckerOrders,
			hasProfile = truckerProfile ~= nil,
			activeRoutes = #truckerActiveRoutes,
		})
		logger.info("SEND helix:data:payload", payload)
	end

	TriggerClientEvent(controller, "helix:data:payload", payload)
end

return Shared
