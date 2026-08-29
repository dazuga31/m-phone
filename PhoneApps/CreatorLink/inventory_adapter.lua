local Domain = require("PhoneApps.CreatorLink.domain")

local InventoryAdapter = {}

local function ResolveProvider(config)
	local providerName = tostring(config and config.Provider or "m-inventory")
	if exports == nil then return nil, "inventory_exports_unavailable" end
	local okProvider, provider = pcall(function() return exports[providerName] end)
	if not okProvider then return nil, "inventory_provider_unavailable" end
	if not provider then return nil, "inventory_provider_unavailable" end
	return provider
end

local function CopyMetadata(source)
	local result = {}
	for key, value in pairs(type(source) == "table" and source or {}) do result[key] = value end
	return result
end

local function RewardUid(claimId, itemIndex, stackIndex)
	local safeClaim = tostring(claimId or "claim"):gsub("[^A-Za-z0-9_-]", "_"):sub(1, 72)
	return string.format("creatorlink_%s_%02d_%02d", safeClaim, itemIndex, stackIndex)
end

function InventoryAdapter.PublicItems(items)
	local result = {}
	for _, item in ipairs(Domain.NormalizeRewardItems(items)) do
		result[#result + 1] = { itemId = item.itemId, label = item.label, quantity = item.quantity }
	end
	return result
end

function InventoryAdapter.RollbackWithProvider(provider, grant)
	if type(grant) ~= "table" or type(grant.rows) ~= "table" then return true end
	local complete = true
	for index = #grant.rows, 1, -1 do
		local row = grant.rows[index]
		local ok, reason = provider:RemoveOwnedItemByUid(grant.playerId, row.uid)
		if ok ~= true and tostring(reason) ~= "item_not_found" then complete = false end
	end
	return complete
end

function InventoryAdapter.GrantWithProvider(provider, controller, items, context, config)
	local normalizedItems = Domain.NormalizeRewardItems(items)
	if #normalizedItems == 0 then return true, { playerId = "", rows = {}, items = {} } end

	local playerId = tostring(provider:GetPlayerId(controller) or "")
	if playerId == "" then return false, { error = "inventory_player_unavailable", rows = {}, items = normalizedItems } end

	local grant = { playerId = playerId, rows = {}, items = normalizedItems }
	for itemIndex, item in ipairs(normalizedItems) do
		local definition = provider:GetItemDefinition(item.itemId)
		if type(definition) ~= "table" then
			grant.error = "inventory_reward_item_unknown"
			grant.itemId = item.itemId
			InventoryAdapter.RollbackWithProvider(provider, grant)
			return false, grant
		end

		local chunks = Domain.SplitQuantity(item.quantity, definition.maxStack)
		for stackIndex, quantity in ipairs(chunks) do
			local uid = RewardUid(context and context.claimId, itemIndex, stackIndex)
			local metadata = CopyMetadata(item.metadata)
			metadata.creatorLinkClaimId = tostring(context and context.claimId or "")
			metadata.creatorLinkRewardType = tostring(context and context.rewardType or "")
			metadata.creatorLinkPartnerId = tostring(context and context.partnerId or "")
			metadata.creatorLinkGrantedAt = tonumber(context and context.grantedAt) or os.time()

			local ok, reason = provider:GiveItem(playerId, item.itemId, {
				uid = uid,
				qty = quantity,
				meta = metadata,
				noStack = true,
				controller = controller,
				containerId = tostring(config and config.ContainerId or "player"),
			})
			if ok ~= true then
				grant.error = tostring(reason or "inventory_reward_grant_failed")
				grant.itemId = item.itemId
				InventoryAdapter.RollbackWithProvider(provider, grant)
				return false, grant
			end
			grant.rows[#grant.rows + 1] = { uid = uid, itemId = item.itemId, quantity = quantity }
		end
	end

	return true, grant
end

function InventoryAdapter.Grant(controller, items, context, config)
	if config and config.Enabled == false then return true, { playerId = "", rows = {}, items = {} } end
	local normalized = Domain.NormalizeRewardItems(items)
	if #normalized == 0 then return true, { playerId = "", rows = {}, items = {} } end
	local provider, providerError = ResolveProvider(config)
	if not provider then return false, { error = providerError, rows = {}, items = normalized } end
	return InventoryAdapter.GrantWithProvider(provider, controller, normalized, context, config)
end

function InventoryAdapter.Rollback(grant, config)
	if type(grant) ~= "table" or type(grant.rows) ~= "table" or #grant.rows == 0 then return true end
	local provider = ResolveProvider(config)
	if not provider then return false end
	return InventoryAdapter.RollbackWithProvider(provider, grant)
end

return InventoryAdapter
