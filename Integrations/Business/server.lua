local Business = {}

local function ResourceName()
	return tostring(Config and Config.Business and Config.Business.Resource or "m-business")
end

local function Call(methodName, ...)
	if not exports then return nil, "business_unavailable" end
	local okProvider, provider = pcall(function() return exports[ResourceName()] end)
	if not okProvider or not provider then return nil, "business_unavailable" end
	local okMethod, method = pcall(function() return provider[methodName] end)
	if not okMethod or method == nil then
		return nil, "business_export_missing:" .. tostring(methodName)
	end
	local ok, first, second, third = pcall(method, provider, ...)
	if not ok then return nil, tostring(first) end
	return first, second, third
end

function Business.IsReady() return Call("IsReady") == true end
function Business.Configure()
	return Call("Configure", {
		locations = Config.ShopLocations or {},
		defaultProducts = Config.ShopProducts or {},
		vatRate = Config.ShopVATRate,
		pricesIncludeVat = Config.ShopPricesIncludeVAT,
		inventory = {
			provider = Config.Inventory,
			priority = Config.InventoryPriority,
			itemMap = Config.InventoryItemMap,
		},
	})
end
function Business.GetShop(shopId) return Call("GetShop", shopId) end
function Business.ListManagedShops() return Call("ListManagedShops") or {} end
function Business.GetAnalytics(playerId, shopId, rangeId) return Call("GetAnalytics", playerId, shopId, rangeId) end
function Business.ClaimShop(playerId, data) return Call("ClaimShop", playerId, data) end
function Business.SetProductPrice(playerId, data) return Call("SetProductPrice", playerId, data) end
function Business.WithdrawBalance(playerId, data) return Call("WithdrawBalance", playerId, data) end
function Business.CreateSupplyOrder(playerId, data) return Call("CreateSupplyOrder", playerId, data) end
function Business.CancelSupplyOrder(playerId, data) return Call("CancelSupplyOrder", playerId, data) end
function Business.FundBusiness(playerId, data) return Call("FundBusiness", playerId, data) end
function Business.MarkSupplyDeliveredByTruckerOrder(orderId) return Call("MarkSupplyDeliveredByTruckerOrder", orderId) end
function Business.CancelSupplyByTruckerOrder(orderId, status, reason, meta) return Call("CancelSupplyByTruckerOrder", orderId, status, reason, meta) end
function Business.SetSupplyStatusByTruckerOrder(orderId, status) return Call("SetSupplyStatusByTruckerOrder", orderId, status) end
function Business.KioskCheckout(controller, data) return Call("KioskCheckout", controller, data) end
function Business.FurnitureGetBootstrap(controller) return Call("FurnitureGetBootstrap", controller) end
function Business.FurnitureGetOrders(controller) return Call("FurnitureGetOrders", controller) end
function Business.FurnitureCheckout(controller, data) return Call("FurnitureCheckout", controller, data) end

return Business
