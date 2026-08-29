local BUILD = "2026-08-15-creatorlink-inventory-v2"
local CreatorConfig = require("PhoneApps.CreatorLink.config")
local Manifests = require("PhoneApps.CreatorLink.manifests")
local DB = require("PhoneApps.CreatorLink.database")
local Domain = require("PhoneApps.CreatorLink.domain")
local InventoryRewards = require("PhoneApps.CreatorLink.inventory_adapter")
local Core = require(tostring(CreatorConfig.Core or "qb"):lower() == "m" and "PhoneApps.CreatorLink.bridge.m" or "PhoneApps.CreatorLink.bridge.qb")

local ready = false
local activationLocks = {}
local failedAttempts = {}
local transactionLocks = {}
local benefitRequestLocks = {}
local applicationLocks = {}

local function Log(level, message)
	print(string.format("[m-phone:creatorlink][server][%s] %s", tostring(level), tostring(message)))
end

local function Identifier(prefix)
	return string.format("%s_%d_%06d", prefix, os.time(), math.random(0, 999999))
end

local NormalizeCode = Domain.NormalizeCode

local function LevelState(reputation)
	local levels = CreatorConfig.PartnerProgress.Levels or {}
	local current = levels[1] or { Id = 1, Label = "Creator", Reputation = 0 }
	local nextLevel
	for _, level in ipairs(levels) do
		if reputation >= (tonumber(level.Reputation) or 0) then current = level
		elseif not nextLevel then nextLevel = level end
	end
	return {
		id = current.Id,
		label = current.Label,
		minimum = current.Reputation,
		nextLabel = nextLevel and nextLevel.Label or "Maximum level",
		nextMinimum = nextLevel and nextLevel.Reputation or current.Reputation,
		progress = nextLevel and math.max(0, math.min(1, (reputation - current.Reputation) / math.max(1, nextLevel.Reputation - current.Reputation))) or 1,
	}
end

local function PublicPartner(partner)
	local levelState = LevelState(tonumber(partner.reputation) or 0)
	return {
		id = partner.partnerId,
		code = partner.code,
		name = partner.displayName,
		channel = partner.channel,
		description = partner.description,
		featured = partner.featured,
		level = levelState.id,
		levelLabel = levelState.label,
	}
end

local function PublicLink(link)
	if not link then return nil end
	return {
		partnerId = link.partnerId,
		code = link.code,
		partnerName = link.partnerName,
		channel = link.channel,
		description = link.description,
		level = link.level,
		cycleNumber = link.cycleNumber,
		activatedAt = link.activatedAt,
		expiresAt = link.expiresAt,
	}
end

local function PublicReward(reward)
	if not reward then return nil end
	local rewardType = tostring(reward.type or reward.rewardType or "")
	local configured = rewardType == "first" and CreatorConfig.Rewards.First or CreatorConfig.Rewards.Repeat
	return {
		type = rewardType,
		cash = tonumber(reward.cash or reward.cashAmount) or 0,
		premiumDays = tonumber(reward.premiumDays) or 0,
		discountBps = tonumber(reward.discountBps) or 0,
		grantedAt = tonumber(reward.grantedAt) or 0,
		items = InventoryRewards.PublicItems(reward.items or (configured and configured.Items)),
	}
end

local function PublicConfiguredReward(reward)
	reward = type(reward) == "table" and reward or {}
	return {
		cash = math.max(0, math.floor(tonumber(reward.Cash) or 0)),
		premiumDays = math.max(0, math.floor(tonumber(reward.PremiumDays) or 0)),
		shopDiscountBps = math.max(0, math.floor(tonumber(reward.ShopDiscountBps) or 0)),
		shopDiscountDays = math.max(0, math.floor(tonumber(reward.ShopDiscountDays) or 0)),
		items = InventoryRewards.PublicItems(reward.Items),
	}
end

local function PublicProgressReward(progress)
	progress = type(progress) == "table" and progress or {}
	return {
		reputation = math.floor(tonumber(progress.Reputation) or 0),
		credits = math.floor(tonumber(progress.Credits) or 0),
		momentum = math.floor(tonumber(progress.Momentum) or 0),
	}
end

local function PublicProgrammeInfo()
	local attribution = CreatorConfig.Attribution or {}
	local rewards = CreatorConfig.Rewards or {}
	local progress = CreatorConfig.PartnerProgress or {}
	local applications = CreatorConfig.Applications or {}
	local premiumCurrency = CreatorConfig.PremiumCurrency or {}
	local finance = CreatorConfig.Finance or {}
	local platformFeeBps = math.max(0, math.min(10000, math.floor(tonumber(finance.HelixPlatformFeeBps) or 3000)))
	local levels = {}
	local benefits = {}

	for _, level in ipairs(progress.Levels or {}) do
		levels[#levels + 1] = {
			id = math.max(1, math.floor(tonumber(level.Id) or 1)),
			label = tostring(level.Label or "Creator"),
			reputation = math.max(0, math.floor(tonumber(level.Reputation) or 0)),
		}
	end

	for _, benefit in ipairs(CreatorConfig.PartnerBenefits or {}) do
		if benefit.Enabled ~= false then
			benefits[#benefits + 1] = {
				id = tostring(benefit.Id or ""),
				label = tostring(benefit.Label or benefit.Id or "Benefit"),
				description = tostring(benefit.Description or ""),
				category = tostring(benefit.Category or "benefit"),
				minimumLevel = math.max(1, math.floor(tonumber(benefit.MinimumLevel) or 1)),
				costCredits = math.max(0, math.floor(tonumber(benefit.CostCredits) or 0)),
			}
		end
	end

	return {
		premiumCurrency = {
			code = tostring(premiumCurrency.Code or "LIX"),
			symbol = tostring(premiumCurrency.Symbol or "Ⱡ"),
		},
		finance = {
			currency = string.upper(tostring(finance.Currency or "LIX")):sub(1, 3),
			symbol = tostring(finance.Symbol or premiumCurrency.Symbol or "Ⱡ"),
			helixPlatformFeeBps = platformFeeBps,
			serverNetBps = 10000 - platformFeeBps,
			commissionBase = tostring(finance.CommissionBase or "server_net"),
		},
		attribution = {
			durationDays = math.max(1, math.floor(tonumber(attribution.DurationDays) or 30)),
			inputCooldownSeconds = math.max(1, math.floor(tonumber(attribution.InputCooldownSeconds) or 2)),
			maximumFailedAttempts = math.max(1, math.floor(tonumber(attribution.MaximumFailedAttempts) or 8)),
			failedAttemptWindowSeconds = math.max(30, math.floor(tonumber(attribution.FailedAttemptWindowSeconds) or 300)),
		},
		rewards = {
			first = PublicConfiguredReward(rewards.First),
			repeatActivation = PublicConfiguredReward(rewards.Repeat),
		},
		progress = {
			momentumMaximum = 1000,
			firstActivation = PublicProgressReward(progress.FirstActivation),
			repeatActivation = PublicProgressReward(progress.RepeatActivation),
			transactionSettled = PublicProgressReward(progress.TransactionSettled),
			levels = levels,
		},
		benefits = benefits,
		applications = {
			enabled = applications.Enabled ~= false,
			minimumAudience = math.max(0, math.floor(tonumber(applications.MinimumAudience) or 0)),
			cooldownDays = math.max(0, math.floor(tonumber(applications.CooldownDays) or 14)),
			defaultCommissionBps = math.max(0, math.floor(tonumber(applications.DefaultCommissionBps) or 0)),
			platforms = applications.Platforms or {},
		},
		rules = {
			oneActiveCode = true,
			selfReferralBlocked = true,
			settledTransactionsOnly = true,
			transactionReversalsSupported = true,
			duplicateClaimsProtected = true,
			codeMinimumLength = 3,
			codeMaximumLength = 24,
		},
	}
end

local function EffectiveBenefits(entitlements, now)
	local result = {
		premium = { active = false, expiresAt = 0, daysLeft = 0 },
		shopDiscount = { active = false, bps = 0, expiresAt = 0, daysLeft = 0 },
	}
	for _, entitlement in ipairs(entitlements or {}) do
		local expiresAt = tonumber(entitlement.expiresAt or 0) or 0
		local daysLeft = expiresAt > 0 and math.max(0, math.ceil((expiresAt - now) / 86400)) or 0
		if entitlement.type == "premium" then
			local betterExpiry = not result.premium.active
				or expiresAt == 0
				or (result.premium.expiresAt ~= 0 and expiresAt > result.premium.expiresAt)
			if betterExpiry then result.premium = { active = true, expiresAt = expiresAt, daysLeft = daysLeft } end
		elseif entitlement.type == "shop_discount" then
			local value = math.max(0, tonumber(entitlement.value or 0) or 0)
			local betterExpiry = not result.shopDiscount.active
				or expiresAt == 0
				or (result.shopDiscount.expiresAt ~= 0 and expiresAt > result.shopDiscount.expiresAt)
			if value > result.shopDiscount.bps or (value == result.shopDiscount.bps and betterExpiry) then
				result.shopDiscount = { active = true, bps = value, expiresAt = expiresAt, daysLeft = daysLeft }
			end
		end
	end
	return result
end

local function FindPartnerBenefit(benefitId)
	local normalized = tostring(benefitId or "")
	for _, benefit in ipairs(CreatorConfig.PartnerBenefits or {}) do
		if tostring(benefit.Id or "") == normalized and benefit.Enabled ~= false then return benefit end
	end
	return nil
end

local function PublicBenefit(benefit, dashboard, hasOpenRequest)
	local minimumLevel = math.max(1, math.floor(tonumber(benefit.MinimumLevel) or 1))
	local costCredits = math.max(0, math.floor(tonumber(benefit.CostCredits) or 0))
	local currentLevel = tonumber(dashboard and dashboard.levelState and dashboard.levelState.id or dashboard and dashboard.level or 0) or 0
	local availableCredits = tonumber(dashboard and dashboard.availableCredits or 0) or 0
	return {
		id = tostring(benefit.Id or ""),
		label = tostring(benefit.Label or benefit.Id or "Benefit"),
		description = tostring(benefit.Description or ""),
		category = tostring(benefit.Category or "benefit"),
		minimumLevel = minimumLevel,
		costCredits = costCredits,
		levelEligible = currentLevel >= minimumLevel,
		affordable = availableCredits >= costCredits,
		requestOpen = hasOpenRequest == true,
	}
end

local function PartnerBenefits(dashboard, requests)
	if not dashboard then return {} end
	local open = {}
	for _, request in ipairs(requests or {}) do
		if request.status == "pending" or request.status == "approved" then open[request.benefitId] = true end
	end
	local result = {}
	for _, benefit in ipairs(CreatorConfig.PartnerBenefits or {}) do
		if benefit.Enabled ~= false then result[#result + 1] = PublicBenefit(benefit, dashboard, open[tostring(benefit.Id or "")]) end
	end
	return result
end

local function PublicDashboard(dashboard)
	if not dashboard then return nil end
	return {
		partnerId = dashboard.partnerId,
		displayName = dashboard.displayName,
		code = dashboard.code,
		channel = dashboard.channel,
		description = dashboard.description,
		level = dashboard.level,
		levelState = dashboard.levelState,
		commissionBps = dashboard.commissionBps,
		reputation = dashboard.reputation,
		credits = dashboard.credits,
		availableCredits = dashboard.availableCredits,
		reservedCredits = dashboard.reservedCredits,
		spentCredits = dashboard.spentCredits,
		momentum = dashboard.momentum,
		pendingBenefitRequests = dashboard.pendingBenefitRequests,
		activePlayers = dashboard.activePlayers,
		firstActivations = dashboard.firstActivations,
		repeatActivations = dashboard.repeatActivations,
		pendingCommission = dashboard.pendingCommission,
		approvedCommission = dashboard.approvedCommission,
	}
end

local function LinkIsActive(link, now)
	return link ~= nil
		and tostring(link.partnerStatus or "") == "active"
		and tostring(link.rewardClaimStatus or "") == "granted"
		and tonumber(link.expiresAt or 0) > tonumber(now or os.time())
end

local function FailureAllowed(accountId)
	local now = os.time()
	local window = math.max(30, tonumber(CreatorConfig.Attribution.FailedAttemptWindowSeconds) or 300)
	local maximum = math.max(1, tonumber(CreatorConfig.Attribution.MaximumFailedAttempts) or 8)
	local state = failedAttempts[accountId]
	if not state or now - state.startedAt >= window then
		failedAttempts[accountId] = { startedAt = now, count = 0, lastAt = 0 }
		state = failedAttempts[accountId]
	end
	if now - state.lastAt < math.max(1, tonumber(CreatorConfig.Attribution.InputCooldownSeconds) or 2) then return false, "try_again_shortly" end
	state.lastAt = now
	if state.count >= maximum then return false, "too_many_attempts" end
	return true
end

local function RecordFailure(accountId)
	local state = failedAttempts[accountId]
	if state then state.count = state.count + 1 end
end

local function TryDatabaseOperation(callback)
	local ok, result = pcall(callback)
	return ok and result == true, ok and nil or tostring(result)
end

local function SetClaimFailure(claimId, reason, reviewRequired)
	local ok, err = pcall(function()
		if reviewRequired then return DB.ReviewClaim(claimId, reason) end
		return DB.FailClaim(claimId, reason)
	end)
	if not ok or err ~= true then
		Log("critical", "failed to update reward claim=" .. tostring(claimId) .. " error=" .. tostring(err))
		return false
	end
	return true
end

local function CreateRewardEntitlements(claim, reward, now)
	local created = true
	if claim.premiumDays > 0 then
		created = DB.CreateEntitlement({
			id = claim.claimId .. ":premium", accountId = claim.accountId, citizenId = claim.citizenId,
			claimId = claim.claimId, type = "premium", value = claim.premiumDays,
			startsAt = now, expiresAt = now + (claim.premiumDays * 86400), createdAt = now,
		}) and created
	end
	local discountDays = math.max(0, math.floor(tonumber(reward.ShopDiscountDays) or 0))
	if claim.discountBps > 0 and discountDays > 0 then
		created = DB.CreateEntitlement({
			id = claim.claimId .. ":shop_discount", accountId = claim.accountId, citizenId = claim.citizenId,
			claimId = claim.claimId, type = "shop_discount", value = claim.discountBps,
			startsAt = now, expiresAt = now + (discountDays * 86400), createdAt = now,
		}) and created
	end
	return created
end

local function State(controller)
	local snapshot, err = Core.GetPlayer(controller)
	if not snapshot then return nil, err end
	if snapshot.accountId == "" then return nil, "account_id_unavailable" end
	local now = os.time()
	local link = DB.GetLink(snapshot.accountId)
	local activeLink = LinkIsActive(link, now) and link or nil
	local partner = DB.GetPartnerByOwner(snapshot.accountId)
	local partners = {}
	for _, entry in ipairs(DB.ListPartners()) do partners[#partners + 1] = PublicPartner(entry) end
	local dashboard = partner and DB.PartnerDashboard(partner.partnerId, now) or nil
	local benefitRequests = dashboard and DB.ListBenefitRequests(dashboard.partnerId, 8) or {}
	local partnerActivity = dashboard and DB.ListPartnerActivity(dashboard.partnerId, 30) or {}
	local partnerTransactions = dashboard and DB.ListPartnerTransactions(dashboard.partnerId, 30) or {}
	if dashboard then
		dashboard.levelState = LevelState(dashboard.reputation)
		dashboard.level = dashboard.levelState.id
	end
	local entitlements = DB.ListActiveEntitlements(snapshot.accountId, now)
	return {
		ok = true,
		serverTime = now,
		profile = { displayName = snapshot.displayName },
		isPartner = partner ~= nil,
		activeLink = PublicLink(activeLink),
		latestReward = PublicReward(DB.LatestReward(snapshot.accountId)),
		supportHistory = DB.ListPlayerCycles(snapshot.accountId, 8),
		benefits = EffectiveBenefits(entitlements, now),
		partners = partners,
		partnerDashboard = PublicDashboard(dashboard),
		partnerBenefits = PartnerBenefits(dashboard, benefitRequests),
		partnerBenefitRequests = benefitRequests,
		partnerActivity = partnerActivity,
		partnerTransactions = partnerTransactions,
		currency = string.upper(tostring(CreatorConfig.Finance and CreatorConfig.Finance.Currency or "LIX")):sub(1, 3),
		programmeInfo = PublicProgrammeInfo(),
		partnerApplication = DB.GetLatestPartnerApplication(snapshot.accountId),
		applicationConfig = {
			enabled = CreatorConfig.Applications and CreatorConfig.Applications.Enabled ~= false,
			minimumAudience = tonumber(CreatorConfig.Applications and CreatorConfig.Applications.MinimumAudience) or 0,
			cooldownDays = tonumber(CreatorConfig.Applications and CreatorConfig.Applications.CooldownDays) or 14,
			platforms = CreatorConfig.Applications and CreatorConfig.Applications.Platforms or {},
		},
		attributionDurationDays = tonumber(CreatorConfig.Attribution.DurationDays) or 30,
	}
end

local function SubmitPartnerApplication(controller, payload)
	local snapshot, playerError = Core.GetPlayer(controller)
	if not snapshot then return { ok = false, error = playerError } end
	if snapshot.accountId == "" then return { ok = false, error = "account_id_unavailable" } end
	if DB.GetPartnerByOwner(snapshot.accountId) then return { ok = false, error = "already_partner" } end
	if not CreatorConfig.Applications or CreatorConfig.Applications.Enabled == false then return { ok = false, error = "applications_disabled" } end
	if applicationLocks[snapshot.accountId] then return { ok = false, error = "application_in_progress" } end

	local displayName = (tostring(payload and payload.displayName or snapshot.displayName or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$") or ""):sub(1, 64)
	local platform = (tostring(payload and payload.platform or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$") or ""):sub(1, 32)
	local channelUrl = (tostring(payload and payload.channelUrl or ""):match("^%s*(.-)%s*$") or ""):sub(1, 240)
	local pitch = (tostring(payload and payload.pitch or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$") or ""):sub(1, 600)
	local audience = math.max(0, math.floor(tonumber(payload and payload.audience) or 0))
	local allowedPlatform = false
	for _, value in ipairs(CreatorConfig.Applications.Platforms or {}) do
		if string.lower(tostring(value)) == string.lower(platform) then platform = tostring(value); allowedPlatform = true; break end
	end
	if displayName == "" then return { ok = false, error = "application_name_required" } end
	if not allowedPlatform then return { ok = false, error = "application_platform_invalid" } end
	if not channelUrl:match("^https?://") then return { ok = false, error = "application_url_invalid" } end
	if audience < math.max(0, tonumber(CreatorConfig.Applications.MinimumAudience) or 0) then return { ok = false, error = "application_audience_required" } end
	if #pitch < 20 then return { ok = false, error = "application_pitch_required" } end

	applicationLocks[snapshot.accountId] = true
	local ok, result = pcall(function()
		local now = os.time()
		local latest = DB.GetLatestPartnerApplication(snapshot.accountId)
		if latest and (latest.status == "pending" or latest.status == "reviewing") then return { ok = false, error = "application_exists" } end
		local cooldown = math.max(0, tonumber(CreatorConfig.Applications.CooldownDays) or 14) * 86400
		if latest and latest.status == "rejected" and now - latest.updatedAt < cooldown then
			return { ok = false, error = "application_cooldown", retryAt = latest.updatedAt + cooldown }
		end
		local application = {
			id = Identifier("creator_application"), accountId = snapshot.accountId, citizenId = snapshot.citizenId,
			displayName = displayName, platform = platform, channelUrl = channelUrl,
			audience = audience, pitch = pitch, createdAt = now,
		}
		if not DB.CreatePartnerApplication(application) then return { ok = false, error = "application_create_failed" } end
		return { ok = true, submitted = true, application = DB.GetLatestPartnerApplication(snapshot.accountId) }
	end)
	applicationLocks[snapshot.accountId] = nil
	if not ok then Log("error", "partner application failed account=" .. snapshot.accountId .. " error=" .. tostring(result)); return { ok = false, error = "application_create_failed" } end
	return result
end

local function CancelPartnerApplication(controller)
	local snapshot, playerError = Core.GetPlayer(controller)
	if not snapshot then return { ok = false, error = playerError } end
	local application = DB.GetLatestPartnerApplication(snapshot.accountId)
	if not application then return { ok = false, error = "application_not_found" } end
	if application.status ~= "pending" then return { ok = false, error = "application_not_pending" } end
	if not DB.CancelPartnerApplication(application.id, snapshot.accountId) then return { ok = false, error = "application_cancel_failed" } end
	return { ok = true, cancelled = true, application = DB.GetLatestPartnerApplication(snapshot.accountId) }
end

local function Activate(controller, payload)
	local snapshot, playerError = Core.GetPlayer(controller)
	if not snapshot then return { ok = false, error = playerError } end
	if snapshot.accountId == "" then return { ok = false, error = "account_id_unavailable" } end
	if activationLocks[snapshot.accountId] then return { ok = false, error = "activation_in_progress" } end
	local allowed, reason = FailureAllowed(snapshot.accountId)
	if not allowed then return { ok = false, error = reason } end
	local code = NormalizeCode(payload and payload.code)
	if #code < 3 then RecordFailure(snapshot.accountId); return { ok = false, error = "code_invalid" } end
	local partner = DB.GetPartnerByCode(code)
	if not partner then RecordFailure(snapshot.accountId); return { ok = false, error = "code_not_found" } end
	if partner.ownerAccountId ~= "" and partner.ownerAccountId == snapshot.accountId then return { ok = false, error = "self_referral_blocked" } end
	local now = os.time()
	local existing = DB.GetLink(snapshot.accountId)
	if LinkIsActive(existing, now) then
		return { ok = false, error = "support_link_active", activeLink = PublicLink(existing) }
	end

	activationLocks[snapshot.accountId] = true
	local ok, result = pcall(function()
		local previousClaims = DB.CountClaims(snapshot.accountId)
		local first = previousClaims == 0
		local reward = first and CreatorConfig.Rewards.First or CreatorConfig.Rewards.Repeat
		local cycle = existing and (existing.cycleNumber + 1) or 1
		local claimId = Identifier("claim")
		local idempotencyKey = string.format("%s:%d", snapshot.accountId, cycle)
		local priorClaim = DB.GetClaimByIdempotencyKey(idempotencyKey)
		if priorClaim then
			if priorClaim.status == "granted" then return { ok = false, error = "reward_already_claimed" } end
			if priorClaim.status == "processing" or priorClaim.status == "review_required" then
				return { ok = false, error = "reward_state_review_required" }
			end
			if priorClaim.status ~= "failed" or not DB.DeleteFailedClaim(priorClaim.claimId) then
				return { ok = false, error = "claim_retry_unavailable" }
			end
		end
		local claim = {
			claimId = claimId, idempotencyKey = idempotencyKey, accountId = snapshot.accountId,
			citizenId = snapshot.citizenId, partnerId = partner.partnerId, cycleNumber = cycle,
			rewardType = first and "first" or "repeat", cashAmount = math.max(0, math.floor(tonumber(reward.Cash) or 0)),
			premiumDays = math.max(0, math.floor(tonumber(reward.PremiumDays) or 0)),
			discountBps = math.max(0, math.floor(tonumber(reward.ShopDiscountBps) or 0)), createdAt = now,
		}
		if not DB.CreateClaim(claim) then return { ok = false, error = "claim_create_failed" } end
		local cashGranted = false
		local inventoryGrant
		if claim.cashAmount > 0 then
			local cashOk, cashError = Core.AddCash(snapshot, claim.cashAmount, "creatorlink_" .. claim.rewardType)
			if not cashOk then DB.FailClaim(claimId, cashError); return { ok = false, error = cashError or "reward_failed" } end
			cashGranted = true
		end
		local duration = math.max(1, tonumber(CreatorConfig.Attribution.DurationDays) or 30) * 86400
		local link = {
			accountId = snapshot.accountId, citizenId = snapshot.citizenId, partnerId = partner.partnerId,
			code = partner.code, cycleNumber = cycle, activatedAt = now, expiresAt = now + duration,
			rewardClaimId = claimId, updatedAt = now,
		}
		local function Rollback(reason)
			local safeToRetry = true
			if not InventoryRewards.Rollback(inventoryGrant, CreatorConfig.InventoryRewards) then
				safeToRetry = false
				Log("critical", "failed to remove inventory rewards claim=" .. claimId)
			end
			local entitlementsRemoved = TryDatabaseOperation(function() return DB.DeleteEntitlementsForClaim(claimId) end)
			if not entitlementsRemoved then
				safeToRetry = false
				Log("critical", "failed to remove reward entitlements claim=" .. claimId)
			end
			local linkRestored
			if existing then
				linkRestored = TryDatabaseOperation(function() return DB.UpsertLink(existing) end)
			else
				linkRestored = TryDatabaseOperation(function() return DB.DeleteLink(snapshot.accountId) end)
			end
			if not linkRestored then
				safeToRetry = false
				Log("critical", "failed to restore attribution account=" .. snapshot.accountId)
			end
			if cashGranted then
				local cashOk, cashError = Core.RemoveCash(snapshot, claim.cashAmount, "creatorlink_rollback_" .. claim.rewardType)
				if not cashOk then
					safeToRetry = false
					Log("critical", "cash rollback failed account=" .. snapshot.accountId .. " error=" .. tostring(cashError))
				end
			end
			SetClaimFailure(claimId, safeToRetry and reason or (reason .. "_rollback_incomplete"), not safeToRetry)
		end
		local linkWritten = TryDatabaseOperation(function() return DB.UpsertLink(link) end)
		if not linkWritten then
			Rollback("link_write_failed")
			return { ok = false, error = "link_write_failed" }
		end
		local inventoryOk, inventoryResult = InventoryRewards.Grant(controller, reward.Items, {
			claimId = claimId,
			rewardType = claim.rewardType,
			partnerId = partner.partnerId,
			grantedAt = now,
		}, CreatorConfig.InventoryRewards)
		inventoryGrant = inventoryResult
		if not inventoryOk then
			Rollback("inventory_reward_failed")
			return { ok = false, error = inventoryResult and inventoryResult.error or "inventory_reward_grant_failed" }
		end
		local entitlementsCreated = TryDatabaseOperation(function() return CreateRewardEntitlements(claim, reward, now) end)
		if not entitlementsCreated then
			Rollback("entitlement_write_failed")
			return { ok = false, error = "entitlement_write_failed" }
		end
		local claimGranted = TryDatabaseOperation(function() return DB.GrantClaim(claimId, now) end)
		if not claimGranted then
			Rollback("claim_finalize_failed")
			return { ok = false, error = "claim_finalize_failed" }
		end
		local progress = first and CreatorConfig.PartnerProgress.FirstActivation or CreatorConfig.PartnerProgress.RepeatActivation
		local progressOk, progressResult = pcall(DB.AddProgress, partner.partnerId, snapshot.accountId,
			first and "first_activation" or "repeat_activation", progress)
		if not progressOk or progressResult ~= true then
			Log("error", "partner progress failed claim=" .. claimId .. " error=" .. tostring(progressResult))
		end
		failedAttempts[snapshot.accountId] = nil
		claim.grantedAt = now
		return {
			ok = true,
			activated = true,
			reward = PublicReward(claim),
			link = PublicLink(DB.GetLink(snapshot.accountId)),
			partner = PublicPartner(partner),
		}
	end)
	activationLocks[snapshot.accountId] = nil
	if not ok then Log("error", "activation failed: " .. tostring(result)); return { ok = false, error = "activation_failed" } end
	return result
end

local function RequestPartnerBenefit(controller, payload)
	local snapshot, playerError = Core.GetPlayer(controller)
	if not snapshot then return { ok = false, error = playerError } end
	if snapshot.accountId == "" then return { ok = false, error = "account_id_unavailable" } end
	local partner = DB.GetPartnerByOwner(snapshot.accountId)
	if not partner then return { ok = false, error = "partner_access_required" } end
	if benefitRequestLocks[partner.partnerId] then return { ok = false, error = "benefit_request_in_progress" } end
	local benefit = FindPartnerBenefit(payload and payload.benefitId)
	if not benefit then return { ok = false, error = "benefit_not_found" } end
	local note = (tostring(payload and payload.note or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$") or ""):sub(1, 280)
	benefitRequestLocks[partner.partnerId] = true
	local ok, result = pcall(function()
		local now = os.time()
		local dashboard = DB.PartnerDashboard(partner.partnerId, now)
		if not dashboard then return { ok = false, error = "partner_access_required" } end
		dashboard.levelState = LevelState(dashboard.reputation)
		dashboard.level = dashboard.levelState.id
		local minimumLevel = math.max(1, math.floor(tonumber(benefit.MinimumLevel) or 1))
		local costCredits = math.max(0, math.floor(tonumber(benefit.CostCredits) or 0))
		if dashboard.level < minimumLevel then return { ok = false, error = "benefit_level_required" } end
		if dashboard.availableCredits < costCredits then return { ok = false, error = "benefit_credits_required" } end
		if DB.HasOpenBenefitRequest(partner.partnerId, benefit.Id) then
			return { ok = false, error = "benefit_request_exists" }
		end
		local request = {
			id = Identifier("benefit"), partnerId = partner.partnerId, ownerAccountId = snapshot.accountId,
			benefitId = tostring(benefit.Id), benefitLabel = tostring(benefit.Label or benefit.Id),
			costCredits = costCredits, note = note, createdAt = now,
		}
		if not DB.CreateBenefitRequest(request) then return { ok = false, error = "benefit_request_failed" } end
		return { ok = true, requested = true, request = DB.GetBenefitRequest(request.id) }
	end)
	benefitRequestLocks[partner.partnerId] = nil
	if not ok then
		Log("error", "benefit request failed partner=" .. partner.partnerId .. " error=" .. tostring(result))
		return { ok = false, error = "benefit_request_failed" }
	end
	return result
end

local function CancelPartnerBenefit(controller, payload)
	local snapshot, playerError = Core.GetPlayer(controller)
	if not snapshot then return { ok = false, error = playerError } end
	if snapshot.accountId == "" then return { ok = false, error = "account_id_unavailable" } end
	local request = DB.GetBenefitRequest(payload and payload.requestId)
	if not request then return { ok = false, error = "benefit_request_not_found" } end
	if request.ownerAccountId ~= snapshot.accountId then return { ok = false, error = "benefit_request_forbidden" } end
	if request.status ~= "pending" then return { ok = false, error = "benefit_request_not_pending" } end
	if not DB.CancelBenefitRequest(request.id) then return { ok = false, error = "benefit_cancel_failed" } end
	local updated = DB.GetBenefitRequest(request.id)
	if not updated or updated.status ~= "cancelled" then return { ok = false, error = "benefit_cancel_failed" } end
	return { ok = true, cancelled = true, request = updated }
end

local function AppRequest(appId, controller, action, payload)
	if not ready then return { ok = false, error = "service_starting" } end
	if tostring(appId or "") ~= Manifests.AppId then return { ok = false, error = "app_not_registered" } end
	if action == "open" or action == "refresh" or action == "getState" then return State(controller) end
	if action == "validateCode" then
		local snapshot, err = Core.GetPlayer(controller)
		if not snapshot then return { ok = false, error = err } end
		local allowed, reason = FailureAllowed(snapshot.accountId)
		if not allowed then return { ok = false, error = reason } end
		local partner = DB.GetPartnerByCode(NormalizeCode(payload and payload.code))
		if not partner then RecordFailure(snapshot.accountId); return { ok = false, error = "code_not_found" } end
		return { ok = true, partner = PublicPartner(partner) }
	end
	if action == "activateCode" then return Activate(controller, payload) end
	if action == "requestPartnerBenefit" then return RequestPartnerBenefit(controller, payload) end
	if action == "cancelPartnerBenefit" then return CancelPartnerBenefit(controller, payload) end
	if action == "submitPartnerApplication" then return SubmitPartnerApplication(controller, payload) end
	if action == "cancelPartnerApplication" then return CancelPartnerApplication(controller) end
	return { ok = false, error = "unknown_action" }
end

local function WidgetRequest(widgetId, controller, action)
	if not ready then return { ok = false, error = "service_starting" } end
	if action ~= "open" and action ~= "refresh" then return { ok = false, error = "unknown_action" } end
	local state, err = State(controller)
	if not state then return { ok = false, error = err } end
	if widgetId == Manifests.PlayerWidgetId then
		return { ok = true, serverTime = state.serverTime, activeLink = state.activeLink, benefits = state.benefits }
	end
	if widgetId == Manifests.PartnerWidgetId then
		if not state.isPartner then return { ok = false, error = "partner_access_required" } end
		return { ok = true, serverTime = state.serverTime, dashboard = state.partnerDashboard }
	end
	return { ok = false, error = "widget_not_registered" }
end

exports("m-phone", "HandleCreatorLinkRequest", AppRequest)
exports("m-phone", "HandleCreatorLinkWidgetRequest", WidgetRequest)
RegisterServerEvent("m-phone:creatorlink:request", function(a, b)
	local controller, request = a, b
	if type(a) ~= "userdata" and type(a) ~= "number" then controller, request = source, a end
	request = type(request) == "table" and request or {}
	local response = AppRequest(Manifests.AppId, controller, tostring(request.action or "getState"), type(request.payload) == "table" and request.payload or {})
	response = type(response) == "table" and response or { ok = false, error = "empty_response" }
	response.requestId = tostring(request.requestId or "")
	TriggerClientEvent(controller, "m-phone:creatorlink:response", response)
end)
exports("m-phone", "GetCreatorLinkPlayerBenefits", function(controller)
	local snapshot, err = Core.GetPlayer(controller)
	if not snapshot then return { ok = false, error = err } end
	local link = DB.GetLink(snapshot.accountId)
	local now = os.time()
	local benefits = EffectiveBenefits(DB.ListActiveEntitlements(snapshot.accountId, now), now)
	return {
		ok = true,
		active = LinkIsActive(link, now),
		link = LinkIsActive(link, now) and PublicLink(link) or nil,
		benefits = benefits,
	}
end)
exports("m-phone", "GetCreatorLinkActiveEntitlement", function(controller, entitlementType)
	local snapshot, err = Core.GetPlayer(controller)
	if not snapshot then return { ok = false, error = err } end
	local now = os.time()
	local entitlement = DB.GetActiveEntitlement(snapshot.accountId, entitlementType, now)
	return { ok = true, active = entitlement ~= nil, entitlement = entitlement }
end)
exports("m-phone", "ReviewCreatorLinkBenefitRequest", function(requestId, status, note)
	local allowed = { approved = true, fulfilled = true, rejected = true, cancelled = true }
	local targetStatus = tostring(status or "")
	if not allowed[targetStatus] then return { ok = false, error = "benefit_status_invalid" } end
	local request = DB.GetBenefitRequest(requestId)
	if not request then return { ok = false, error = "benefit_request_not_found" } end
	local transitionAllowed = (request.status == "pending" and (targetStatus == "approved" or targetStatus == "rejected" or targetStatus == "cancelled"))
		or (request.status == "approved" and (targetStatus == "fulfilled" or targetStatus == "rejected" or targetStatus == "cancelled"))
	if not transitionAllowed then return { ok = false, error = "benefit_status_transition_invalid" } end
	local normalizedNote = (tostring(note or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$") or ""):sub(1, 280)
	if not DB.UpdateBenefitRequest(request.id, request.status, targetStatus, normalizedNote) then
		return { ok = false, error = "benefit_request_update_failed" }
	end
	local updated = DB.GetBenefitRequest(request.id)
	if not updated or updated.status ~= targetStatus then
		return { ok = false, error = "benefit_request_update_failed" }
	end
	return { ok = true, request = updated }
end)
exports("m-phone", "GetCreatorLinkPartnerBenefitRequests", function(partnerId, limit)
	local normalizedPartnerId = tostring(partnerId or "")
	if normalizedPartnerId == "" or not DB.GetPartner(normalizedPartnerId) then
		return { ok = false, error = "partner_not_found" }
	end
	return { ok = true, requests = DB.ListBenefitRequests(normalizedPartnerId, limit) }
end)
exports("m-phone", "GetCreatorLinkPartnerApplications", function(status, limit)
	if not ready then return { ok = false, error = "service_starting" } end
	local allowed = { [""] = true, pending = true, reviewing = true, approved = true, rejected = true, cancelled = true }
	local normalizedStatus = tostring(status or "")
	if not allowed[normalizedStatus] then return { ok = false, error = "application_status_invalid" } end
	return { ok = true, applications = DB.ListPartnerApplications(normalizedStatus, limit) }
end)
exports("m-phone", "ReviewCreatorLinkPartnerApplication", function(applicationId, status, note)
	if not ready then return { ok = false, error = "service_starting" } end
	local targetStatus = tostring(status or "")
	local allowed = { reviewing = true, approved = true, rejected = true }
	if not allowed[targetStatus] then return { ok = false, error = "application_status_invalid" } end
	local id = tostring(applicationId or "")
	local current = DB.GetPartnerApplication(id)
	if not current then return { ok = false, error = "application_not_found" } end
	local transitionAllowed = current.status == "pending" and (targetStatus == "reviewing" or targetStatus == "approved" or targetStatus == "rejected")
		or current.status == "reviewing" and (targetStatus == "approved" or targetStatus == "rejected")
	if not transitionAllowed then return { ok = false, error = "application_status_transition_invalid" } end
	local normalizedNote = (tostring(note or ""):gsub("[%c]", " "):match("^%s*(.-)%s*$") or ""):sub(1, 500)
	local partnerToActivate
	if targetStatus == "approved" then
		local existingPartner = DB.GetPartnerByOwnerAny(current.accountId)
		if not existingPartner then
			local baseCode = NormalizeCode(current.displayName):sub(1, 16)
			if #baseCode < 3 then baseCode = "CREATOR" end
			local code = baseCode
			local suffix = 1
			while DB.GetPartnerByCodeAny(code) and suffix < 1000 do
				suffix = suffix + 1
				code = (baseCode:sub(1, 12) .. tostring(suffix)):sub(1, 16)
			end
			if DB.GetPartnerByCodeAny(code) then return { ok = false, error = "partner_code_unavailable" } end
			partnerToActivate = {
				partnerId = Identifier("creator"), ownerAccountId = current.accountId, code = code,
				displayName = current.displayName, channel = current.platform,
				description = current.pitch:sub(1, 280), status = "pending_activation", featured = false,
				commissionBps = tonumber(CreatorConfig.Applications and CreatorConfig.Applications.DefaultCommissionBps) or 0,
				createdAt = os.time(),
			}
			if not DB.CreatePartner(partnerToActivate) then return { ok = false, error = "partner_create_failed" } end
		elseif existingPartner.status == "pending_activation" then
			partnerToActivate = existingPartner
		elseif existingPartner.status ~= "active" then
			return { ok = false, error = "partner_account_conflict" }
		end
	end
	if partnerToActivate and not DB.UpdatePartnerStatus(partnerToActivate.partnerId, "pending_activation", "active") then
		return { ok = false, error = "partner_activation_failed" }
	end
	if not DB.UpdatePartnerApplication(id, current.status, targetStatus, normalizedNote) then
		return { ok = false, error = "application_update_failed" }
	end
	return {
		ok = true,
		application = DB.GetLatestPartnerApplication(current.accountId),
		partner = DB.GetPartnerByOwner(current.accountId),
	}
end)
exports("m-phone", "RecordCreatorLinkTransaction", function(transactionId, controller, amountLix, currency)
	local snapshot, err = Core.GetPlayer(controller)
	if not snapshot then return { ok = false, error = err } end
	local link = DB.GetLink(snapshot.accountId)
	local active = LinkIsActive(link, os.time()) and link or nil
	local amount = math.max(0, math.floor(tonumber(amountLix) or 0))
	if amount <= 0 then return { ok = false, error = "transaction_amount_invalid" } end
	local rate = active and math.max(0, math.floor(tonumber(active.commissionBps) or 0)) or 0
	local finance = CreatorConfig.Finance or {}
	local commissionCurrency = string.upper(tostring(finance.Currency or "LIX")):sub(1, 3)
	local normalizedCurrency = string.upper(tostring(currency or commissionCurrency)):sub(1, 3)
	if not string.match(normalizedCurrency, "^[A-Z][A-Z][A-Z]$") then
		return { ok = false, error = "transaction_currency_invalid" }
	end
	if normalizedCurrency ~= commissionCurrency then
		return { ok = false, error = "transaction_currency_unsupported" }
	end
	-- TODO: this export is intentionally dormant until an authoritative LIX purchase API exists.
	local calculated = Domain.CalculateCommission(amount, finance.HelixPlatformFeeBps or 3000, rate)
	local normalizedId = (tostring(transactionId or ""):match("^%s*(.-)%s*$") or ""):sub(1, 128)
	local record = {
		id = normalizedId, accountId = snapshot.accountId,
		partnerId = active and active.partnerId or "", partnerCode = active and active.code or "",
		commissionBps = rate, amountLix = calculated.amountLix, helixFeeLix = calculated.helixFeeLix,
		serverNetLix = calculated.serverNetLix, commissionLix = calculated.commissionLix,
		currency = normalizedCurrency, status = "pending", createdAt = os.time(),
	}
	if record.id == "" then return { ok = false, error = "transaction_id_required" } end
	if transactionLocks[record.id] then return { ok = false, error = "transaction_update_in_progress" } end
	transactionLocks[record.id] = true
	local ok, result = pcall(function()
		local existingTransaction = DB.GetTransaction(record.id)
		if existingTransaction then
			local sameRequest = existingTransaction.accountId == record.accountId
				and existingTransaction.amountLix == record.amountLix
				and existingTransaction.currency == record.currency
			if not sameRequest then return { ok = false, error = "transaction_id_conflict" } end
			return { ok = true, idempotent = true, transaction = existingTransaction }
		end
		if not DB.RecordTransaction(record) then return { ok = false, error = "transaction_write_failed" } end
		local persisted = DB.GetTransaction(record.id)
		if not persisted then return { ok = false, error = "transaction_write_failed" } end
		local sameRequest = persisted.accountId == record.accountId
			and persisted.amountLix == record.amountLix
			and persisted.currency == record.currency
		if not sameRequest then return { ok = false, error = "transaction_id_conflict" } end
		return { ok = true, transaction = persisted }
	end)
	transactionLocks[record.id] = nil
	if not ok then
		Log("error", "transaction write failed id=" .. record.id .. " error=" .. tostring(result))
		return { ok = false, error = "transaction_write_failed" }
	end
	return result
end)

local function ChangeTransactionStatus(transactionId, targetStatus)
	local id = tostring(transactionId or "")
	if id == "" then return { ok = false, error = "transaction_id_required" } end
	if transactionLocks[id] then return { ok = false, error = "transaction_update_in_progress" } end
	transactionLocks[id] = true
	local ok, result = pcall(function()
		local transaction = DB.GetTransaction(id)
		if not transaction then return { ok = false, error = "transaction_not_found" } end
		if transaction.status == targetStatus then return { ok = true, idempotent = true, transaction = transaction } end
		if targetStatus == "settled" and transaction.status ~= "pending" then
			return { ok = false, error = "transaction_not_pending", transaction = transaction }
		end
		local wasSettled = transaction.status == "settled"
		if not DB.UpdateTransaction(id, targetStatus) then return { ok = false, error = "transaction_update_failed" } end
		if transaction.partnerId ~= "" then
			local configured = CreatorConfig.PartnerProgress.TransactionSettled or {}
			local direction = targetStatus == "settled" and 1 or (wasSettled and -1 or 0)
			if direction ~= 0 then
				local progress = {
					Reputation = direction * (tonumber(configured.Reputation) or 0),
					Credits = direction * (tonumber(configured.Credits) or 0),
					Momentum = direction * (tonumber(configured.Momentum) or 0),
				}
				local progressOk, progressResult = pcall(DB.AddProgress, transaction.partnerId, transaction.accountId,
					targetStatus == "settled" and "transaction_settled" or "transaction_reversed", progress)
				if not progressOk or progressResult ~= true then
					Log("error", "transaction progress failed id=" .. id .. " error=" .. tostring(progressResult))
				end
			end
		end
		transaction.status = targetStatus
		transaction.updatedAt = os.time()
		return { ok = true, transaction = transaction }
	end)
	transactionLocks[id] = nil
	if not ok then
		Log("error", "transaction update failed id=" .. id .. " error=" .. tostring(result))
		return { ok = false, error = "transaction_update_failed" }
	end
	return result
end

exports("m-phone", "SettleCreatorLinkTransaction", function(transactionId)
	return ChangeTransactionStatus(transactionId, "settled")
end)
exports("m-phone", "ReverseCreatorLinkTransaction", function(transactionId)
	return ChangeTransactionStatus(transactionId, "reversed")
end)

local maximumStartupAttempts = math.max(1, math.floor(tonumber(CreatorConfig.Startup and CreatorConfig.Startup.MaximumAttempts) or 60))
local startupRetryDelay = math.max(250, math.floor(tonumber(CreatorConfig.Startup and CreatorConfig.Startup.RetryDelayMs) or 1000))

local function InitializeService()
	if ready then return true end
	local ok, initError = pcall(function()
		if CreatorConfig.Tests and CreatorConfig.Tests.RunOnStartup == true then
			local tests = require("PhoneApps.CreatorLink.tests.domain_spec")
			assert(tests.Run() == true, "CreatorLink tests failed")
			Log("test", "domain and inventory adapter tests passed")
		end
		DB.Init()
		DB.SeedPartners(CreatorConfig.Partners)
		DB.BackfillEntitlements(CreatorConfig.Rewards)
	end)
	if not ok then return false, tostring(initError) end
	ready = true
	Log("ready", "database initialized provider=" .. tostring(CreatorConfig.DatabaseProvider or CreatorConfig.Core or "unknown"))
	return true
end

if Timer and type(Timer.SetTimeout) == "function" then
	local startupAttempts = 0
	local function InitializeWithRetry()
		startupAttempts = startupAttempts + 1
		local initialized, initError = InitializeService()
		if initialized then return end
		if startupAttempts == 1 or startupAttempts % 10 == 0 then
			Log("warn", "database unavailable attempt=" .. startupAttempts .. "/" .. maximumStartupAttempts .. " error=" .. tostring(initError))
		end
		if startupAttempts < maximumStartupAttempts then
			Timer.SetTimeout(InitializeWithRetry, startupRetryDelay)
		else
			Log("error", "database initialization exhausted all attempts")
		end
	end
	Timer.SetTimeout(InitializeWithRetry, 50)
else
	local initialized, initError = InitializeService()
	if not initialized then Log("error", "database initialization failed: " .. tostring(initError)) end
end

Log("ready", "resource started build=" .. BUILD)


return { HandleRequest = AppRequest, HandleWidgetRequest = WidgetRequest }
