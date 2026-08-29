local Domain = {}

function Domain.NormalizeCode(value)
	return string.upper((tostring(value or ""):gsub("[^A-Za-z0-9_-]", ""))):sub(1, 24)
end

function Domain.NormalizeRewardItems(items)
	local normalized = {}
	for _, item in ipairs(type(items) == "table" and items or {}) do
		local itemId = tostring(item.ItemId or item.itemId or ""):lower()
		local quantity = math.max(0, math.floor(tonumber(item.Quantity or item.quantity) or 0))
		if itemId ~= "" and quantity > 0 then
			normalized[#normalized + 1] = {
				itemId = itemId,
				label = tostring(item.Label or item.label or itemId),
				quantity = quantity,
				metadata = type(item.Metadata or item.metadata) == "table" and (item.Metadata or item.metadata) or {},
			}
		end
	end
	return normalized
end

function Domain.SplitQuantity(quantity, maximum)
	local chunks = {}
	local remaining = math.max(0, math.floor(tonumber(quantity) or 0))
	local stackMaximum = math.max(1, math.floor(tonumber(maximum) or 1))
	while remaining > 0 do
		local chunk = math.min(remaining, stackMaximum)
		chunks[#chunks + 1] = chunk
		remaining = remaining - chunk
	end
	return chunks
end

function Domain.CalculateCommission(amountLix, platformFeeBps, commissionBps)
	local amount = math.max(0, math.floor(tonumber(amountLix) or 0))
	local platformRate = math.max(0, math.min(10000, math.floor(tonumber(platformFeeBps) or 0)))
	local creatorRate = math.max(0, math.min(10000, math.floor(tonumber(commissionBps) or 0)))
	local platformFee = math.floor(amount * platformRate / 10000)
	local serverNet = math.max(0, amount - platformFee)
	return {
		amountLix = amount,
		helixFeeLix = platformFee,
		serverNetLix = serverNet,
		commissionLix = math.floor(serverNet * creatorRate / 10000),
	}
end

return Domain
