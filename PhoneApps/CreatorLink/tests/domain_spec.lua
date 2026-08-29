local Domain = require("PhoneApps.CreatorLink.domain")
local InventoryAdapter = require("PhoneApps.CreatorLink.inventory_adapter")

local Spec = {}

local function Equal(actual, expected, label)
	if actual ~= expected then error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual))) end
end

local function Provider(failAt)
	local provider = { rows = {}, giveCalls = 0 }
	function provider:GetPlayerId(controller) return controller and controller.playerId or "" end
	function provider:GetItemDefinition(itemId)
		if itemId == "food_burger" then return { maxStack = 10 } end
		if itemId == "iphone" then return { maxStack = 1 } end
		return nil
	end
	function provider:GiveItem(_, itemId, options)
		self.giveCalls = self.giveCalls + 1
		if failAt and self.giveCalls == failAt then return false, "inventory_full" end
		self.rows[options.uid] = { itemId = itemId, qty = options.qty, meta = options.meta }
		return true, "ok", { uid = options.uid }
	end
	function provider:RemoveOwnedItemByUid(_, uid)
		if not self.rows[uid] then return false, "item_not_found" end
		self.rows[uid] = nil
		return true, "ok"
	end
	return provider
end

function Spec.Run()
	Equal(Domain.NormalizeCode(" be lik! "), "BELIK", "normalize code")
	local chunks = Domain.SplitQuantity(23, 10)
	Equal(#chunks, 3, "stack count")
	Equal(chunks[1], 10, "stack one")
	Equal(chunks[3], 3, "stack three")

	local finance = Domain.CalculateCommission(1000, 3000, 500)
	Equal(finance.helixFeeLix, 300, "HELIX fee")
	Equal(finance.serverNetLix, 700, "server net")
	Equal(finance.commissionLix, 35, "creator commission")

	local provider = Provider()
	local granted, grant = InventoryAdapter.GrantWithProvider(provider, { playerId = "player-1" }, {
		{ ItemId = "food_burger", Quantity = 12, Label = "Burger" },
		{ ItemId = "iphone", Quantity = 1, Label = "Phone" },
	}, { claimId = "claim-1", rewardType = "first", partnerId = "belik", grantedAt = 100 }, {})
	Equal(granted, true, "inventory grant")
	Equal(#grant.rows, 3, "granted rows")
	Equal(InventoryAdapter.RollbackWithProvider(provider, grant), true, "inventory rollback")
	Equal(next(provider.rows), nil, "rollback emptied rows")

	local partialProvider = Provider(2)
	local partialOk, partialGrant = InventoryAdapter.GrantWithProvider(partialProvider, { playerId = "player-2" }, {
		{ ItemId = "food_burger", Quantity = 12 },
	}, { claimId = "claim-2" }, {})
	Equal(partialOk, false, "partial grant fails")
	Equal(partialGrant.error, "inventory_full", "partial grant reason")
	Equal(next(partialProvider.rows), nil, "partial grant rolls back")

	return true
end

return Spec
