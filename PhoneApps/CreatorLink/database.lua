local CreatorConfig = require("PhoneApps.CreatorLink.config")
local DB = {}

local Bridge

local function CoreBridge()
	if Bridge then return Bridge end
	local name = tostring(CreatorConfig.Core or "qb"):lower()
	Bridge = require(name == "m" and "PhoneApps.CreatorLink.bridge.m" or "PhoneApps.CreatorLink.bridge.qb")
	return Bridge
end

local function Execute(sql, params)
	local result, err = CoreBridge().Database("Execute", sql, params or {})
	if result == nil then error(err or "database_execute_failed") end
	return result == true
end

local function RequireExecute(sql, params)
	if not Execute(sql, params) then error("database_execute_failed") end
	return true
end

local function Select(sql, params)
	local result, err = CoreBridge().Database("Select", sql, params or {})
	if result == nil then error(err or "database_select_failed") end
	return result
end

local function Count(rows)
	if rows == nil then return 0 end
	for _, methodName in ipairs({ "Num", "Length", "Count" }) do
		local okMethod, method = pcall(function() return rows[methodName] end)
		if okMethod and method ~= nil then
			local okValue, value = pcall(method, rows)
			if okValue and tonumber(value) ~= nil then return math.max(0, math.floor(tonumber(value))) end
		end
	end
	if type(rows) == "table" then return #rows end
	return 0
end

local function At(rows, index)
	if rows == nil then return nil end
	local oneBasedIndex = math.max(1, math.floor(tonumber(index) or 1))
	if oneBasedIndex > Count(rows) then return nil end
	local okGetter, getter = pcall(function() return rows.Get end)
	if okGetter and getter ~= nil then
		local okRow, row = pcall(getter, rows, oneBasedIndex - 1)
		return okRow and row or nil
	end
	if type(rows) == "table" then return rows[oneBasedIndex] end
	return nil
end

local function Value(row, ...)
	if row == nil then return nil end
	local columns
	local ok, result = pcall(function() return row.Columns end)
	if ok then columns = result end
	for index = 1, select("#", ...) do
		local key = select(index, ...)
		if type(columns) == "userdata" then
			local okFind, find = pcall(function() return columns.Find end)
			if okFind and find ~= nil then
				local foundOk, found = pcall(find, columns, key)
				if foundOk and found ~= nil then return found end
			end
		elseif type(columns) == "table" and columns[key] ~= nil then
			return columns[key]
		elseif type(row) == "table" and row[key] ~= nil then
			return row[key]
		end
	end
	return nil
end

local function First(rows)
	return Count(rows) > 0 and At(rows, 1) or nil
end

local function HasColumn(tableName, columnName)
	local rows = Select("PRAGMA table_info(" .. tostring(tableName) .. ")", {})
	for index = 1, Count(rows) do
		if tostring(Value(At(rows, index), "name") or "") == tostring(columnName) then return true end
	end
	return false
end

local function Row(row)
	if not row then return nil end
	return {
		partnerId = tostring(Value(row, "partner_id") or ""),
		ownerAccountId = tostring(Value(row, "owner_account_id") or ""),
		code = tostring(Value(row, "code") or ""),
		displayName = tostring(Value(row, "display_name") or ""),
		channel = tostring(Value(row, "channel") or ""),
		description = tostring(Value(row, "description") or ""),
		status = tostring(Value(row, "status") or ""),
		featured = tonumber(Value(row, "featured") or 0) == 1,
		level = tonumber(Value(row, "level") or 1) or 1,
		commissionBps = tonumber(Value(row, "commission_bps") or 0) or 0,
		reputation = tonumber(Value(row, "reputation") or 0) or 0,
		credits = tonumber(Value(row, "credits") or 0) or 0,
		momentum = tonumber(Value(row, "momentum") or 0) or 0,
		activePlayers = tonumber(Value(row, "active_players") or 0) or 0,
		firstActivations = tonumber(Value(row, "first_activations") or 0) or 0,
		repeatActivations = tonumber(Value(row, "repeat_activations") or 0) or 0,
		pendingCommission = tonumber(Value(row, "pending_commission") or 0) or 0,
		approvedCommission = tonumber(Value(row, "approved_commission") or 0) or 0,
	}
end

function DB.Init()
	RequireExecute([[CREATE TABLE IF NOT EXISTS creatorlink_partners (
		partner_id TEXT PRIMARY KEY,
		owner_account_id TEXT NOT NULL DEFAULT '',
		code TEXT NOT NULL UNIQUE,
		display_name TEXT NOT NULL,
		channel TEXT NOT NULL DEFAULT '',
		description TEXT NOT NULL DEFAULT '',
		status TEXT NOT NULL DEFAULT 'active',
		featured INTEGER NOT NULL DEFAULT 0,
		level INTEGER NOT NULL DEFAULT 1,
		commission_bps INTEGER NOT NULL DEFAULT 0,
		reputation INTEGER NOT NULL DEFAULT 0,
		credits INTEGER NOT NULL DEFAULT 0,
		momentum INTEGER NOT NULL DEFAULT 0,
		created_at INTEGER NOT NULL,
		updated_at INTEGER NOT NULL
	)]])
	RequireExecute([[CREATE TABLE IF NOT EXISTS creatorlink_player_links (
		account_id TEXT PRIMARY KEY,
		citizen_id TEXT NOT NULL DEFAULT '',
		partner_id TEXT NOT NULL,
		code TEXT NOT NULL,
		cycle_number INTEGER NOT NULL DEFAULT 1,
		activated_at INTEGER NOT NULL,
		expires_at INTEGER NOT NULL,
		reward_claim_id TEXT NOT NULL,
		updated_at INTEGER NOT NULL
	)]])
	RequireExecute([[CREATE TABLE IF NOT EXISTS creatorlink_reward_claims (
		claim_id TEXT PRIMARY KEY,
		idempotency_key TEXT NOT NULL UNIQUE,
		account_id TEXT NOT NULL,
		citizen_id TEXT NOT NULL DEFAULT '',
		partner_id TEXT NOT NULL,
		cycle_number INTEGER NOT NULL,
		reward_type TEXT NOT NULL,
		cash_amount INTEGER NOT NULL DEFAULT 0,
		premium_days INTEGER NOT NULL DEFAULT 0,
		discount_bps INTEGER NOT NULL DEFAULT 0,
		status TEXT NOT NULL,
		error TEXT NOT NULL DEFAULT '',
		created_at INTEGER NOT NULL,
		granted_at INTEGER NOT NULL DEFAULT 0
	)]])
	RequireExecute([[CREATE TABLE IF NOT EXISTS creatorlink_points_ledger (
		entry_id TEXT PRIMARY KEY,
		partner_id TEXT NOT NULL,
		account_id TEXT NOT NULL DEFAULT '',
		event_type TEXT NOT NULL,
		reputation INTEGER NOT NULL DEFAULT 0,
		credits INTEGER NOT NULL DEFAULT 0,
		momentum INTEGER NOT NULL DEFAULT 0,
		created_at INTEGER NOT NULL
	)]])
	RequireExecute([[CREATE TABLE IF NOT EXISTS creatorlink_transactions (
		transaction_id TEXT PRIMARY KEY,
		account_id TEXT NOT NULL,
		partner_id TEXT NOT NULL DEFAULT '',
		partner_code TEXT NOT NULL DEFAULT '',
		commission_bps INTEGER NOT NULL DEFAULT 0,
		amount_minor INTEGER NOT NULL DEFAULT 0,
		commission_minor INTEGER NOT NULL DEFAULT 0,
		amount_lix INTEGER NOT NULL DEFAULT 0,
		helix_fee_lix INTEGER NOT NULL DEFAULT 0,
		server_net_lix INTEGER NOT NULL DEFAULT 0,
		commission_lix INTEGER NOT NULL DEFAULT 0,
		currency TEXT NOT NULL DEFAULT 'LIX',
		status TEXT NOT NULL DEFAULT 'pending',
		created_at INTEGER NOT NULL,
		updated_at INTEGER NOT NULL
	)]])
	RequireExecute([[CREATE TABLE IF NOT EXISTS creatorlink_entitlements (
		entitlement_id TEXT PRIMARY KEY,
		account_id TEXT NOT NULL,
		citizen_id TEXT NOT NULL DEFAULT '',
		claim_id TEXT NOT NULL,
		entitlement_type TEXT NOT NULL,
		value_integer INTEGER NOT NULL DEFAULT 0,
		starts_at INTEGER NOT NULL,
		expires_at INTEGER NOT NULL DEFAULT 0,
		status TEXT NOT NULL DEFAULT 'active',
		metadata TEXT NOT NULL DEFAULT '',
		created_at INTEGER NOT NULL,
		updated_at INTEGER NOT NULL,
		UNIQUE(claim_id, entitlement_type)
	)]])
	RequireExecute([[CREATE TABLE IF NOT EXISTS creatorlink_benefit_requests (
		request_id TEXT PRIMARY KEY,
		partner_id TEXT NOT NULL,
		owner_account_id TEXT NOT NULL,
		benefit_id TEXT NOT NULL,
		benefit_label TEXT NOT NULL,
		cost_credits INTEGER NOT NULL DEFAULT 0,
		status TEXT NOT NULL DEFAULT 'pending',
		note TEXT NOT NULL DEFAULT '',
		review_note TEXT NOT NULL DEFAULT '',
		created_at INTEGER NOT NULL,
		updated_at INTEGER NOT NULL
	)]])
	RequireExecute([[CREATE TABLE IF NOT EXISTS creatorlink_partner_applications (
		application_id TEXT PRIMARY KEY,
		account_id TEXT NOT NULL,
		citizen_id TEXT NOT NULL DEFAULT '',
		display_name TEXT NOT NULL,
		platform TEXT NOT NULL,
		channel_url TEXT NOT NULL,
		audience INTEGER NOT NULL DEFAULT 0,
		pitch TEXT NOT NULL DEFAULT '',
		status TEXT NOT NULL DEFAULT 'pending',
		review_note TEXT NOT NULL DEFAULT '',
		created_at INTEGER NOT NULL,
		updated_at INTEGER NOT NULL
	)]])
	if not HasColumn("creatorlink_benefit_requests", "review_note") then
		RequireExecute("ALTER TABLE creatorlink_benefit_requests ADD COLUMN review_note TEXT NOT NULL DEFAULT ''")
	end
	if not HasColumn("creatorlink_transactions", "amount_lix") then
		RequireExecute("ALTER TABLE creatorlink_transactions ADD COLUMN amount_lix INTEGER NOT NULL DEFAULT 0")
	end
	if not HasColumn("creatorlink_transactions", "helix_fee_lix") then
		RequireExecute("ALTER TABLE creatorlink_transactions ADD COLUMN helix_fee_lix INTEGER NOT NULL DEFAULT 0")
	end
	if not HasColumn("creatorlink_transactions", "server_net_lix") then
		RequireExecute("ALTER TABLE creatorlink_transactions ADD COLUMN server_net_lix INTEGER NOT NULL DEFAULT 0")
	end
	if not HasColumn("creatorlink_transactions", "commission_lix") then
		RequireExecute("ALTER TABLE creatorlink_transactions ADD COLUMN commission_lix INTEGER NOT NULL DEFAULT 0")
	end
	RequireExecute("CREATE INDEX IF NOT EXISTS idx_creatorlink_links_partner_expiry ON creatorlink_player_links(partner_id, expires_at)")
	RequireExecute("CREATE INDEX IF NOT EXISTS idx_creatorlink_claims_account ON creatorlink_reward_claims(account_id, created_at)")
	RequireExecute("CREATE INDEX IF NOT EXISTS idx_creatorlink_points_partner ON creatorlink_points_ledger(partner_id, created_at)")
	RequireExecute("CREATE INDEX IF NOT EXISTS idx_creatorlink_tx_partner_status ON creatorlink_transactions(partner_id, status)")
	RequireExecute("CREATE INDEX IF NOT EXISTS idx_creatorlink_entitlements_account ON creatorlink_entitlements(account_id, status, expires_at)")
	RequireExecute("CREATE INDEX IF NOT EXISTS idx_creatorlink_benefit_partner ON creatorlink_benefit_requests(partner_id, status, created_at)")
	RequireExecute("CREATE INDEX IF NOT EXISTS idx_creatorlink_application_account ON creatorlink_partner_applications(account_id, created_at)")
	RequireExecute([[CREATE UNIQUE INDEX IF NOT EXISTS idx_creatorlink_application_open_unique
		ON creatorlink_partner_applications(account_id) WHERE status IN ('pending', 'reviewing')]])
	RequireExecute([[CREATE UNIQUE INDEX IF NOT EXISTS idx_creatorlink_benefit_open_unique
		ON creatorlink_benefit_requests(partner_id, benefit_id) WHERE status IN ('pending', 'approved')]])
end

function DB.GetLatestPartnerApplication(accountId)
	local row = First(Select([[SELECT * FROM creatorlink_partner_applications
		WHERE account_id = ? ORDER BY created_at DESC LIMIT 1]], { tostring(accountId or "") }))
	if not row then return nil end
	return {
		id = tostring(Value(row, "application_id") or ""),
		accountId = tostring(Value(row, "account_id") or ""),
		displayName = tostring(Value(row, "display_name") or ""),
		platform = tostring(Value(row, "platform") or ""),
		channelUrl = tostring(Value(row, "channel_url") or ""),
		audience = tonumber(Value(row, "audience") or 0) or 0,
		pitch = tostring(Value(row, "pitch") or ""),
		status = tostring(Value(row, "status") or "pending"),
		reviewNote = tostring(Value(row, "review_note") or ""),
		createdAt = tonumber(Value(row, "created_at") or 0) or 0,
		updatedAt = tonumber(Value(row, "updated_at") or 0) or 0,
	}
end

function DB.GetPartnerApplication(applicationId)
	local row = First(Select("SELECT * FROM creatorlink_partner_applications WHERE application_id = ? LIMIT 1", {
		tostring(applicationId or ""),
	}))
	if not row then return nil end
	return {
		id = tostring(Value(row, "application_id") or ""),
		accountId = tostring(Value(row, "account_id") or ""),
		citizenId = tostring(Value(row, "citizen_id") or ""),
		displayName = tostring(Value(row, "display_name") or ""),
		platform = tostring(Value(row, "platform") or ""),
		channelUrl = tostring(Value(row, "channel_url") or ""),
		audience = tonumber(Value(row, "audience") or 0) or 0,
		pitch = tostring(Value(row, "pitch") or ""),
		status = tostring(Value(row, "status") or "pending"),
		reviewNote = tostring(Value(row, "review_note") or ""),
		createdAt = tonumber(Value(row, "created_at") or 0) or 0,
		updatedAt = tonumber(Value(row, "updated_at") or 0) or 0,
	}
end

function DB.CreatePartnerApplication(application)
	return Execute([[INSERT INTO creatorlink_partner_applications (
		application_id, account_id, citizen_id, display_name, platform, channel_url,
		audience, pitch, status, review_note, created_at, updated_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', '', ?, ?)]], {
		application.id, application.accountId, application.citizenId, application.displayName,
		application.platform, application.channelUrl, application.audience, application.pitch,
		application.createdAt, application.createdAt,
	})
end

function DB.CancelPartnerApplication(applicationId, accountId)
	return Execute([[UPDATE creatorlink_partner_applications SET status = 'cancelled', updated_at = ?
		WHERE application_id = ? AND account_id = ? AND status = 'pending']], {
		os.time(), tostring(applicationId or ""), tostring(accountId or ""),
	})
end

function DB.ListPartnerApplications(status, limit)
	local safeLimit = math.max(1, math.min(100, math.floor(tonumber(limit) or 25)))
	local normalizedStatus = tostring(status or "")
	local sql = "SELECT * FROM creatorlink_partner_applications"
	local params = {}
	if normalizedStatus ~= "" then
		sql = sql .. " WHERE status = ?"
		params[1] = normalizedStatus
	end
	local rows = Select(sql .. " ORDER BY created_at DESC LIMIT " .. tostring(safeLimit), params)
	local result = {}
	for index = 1, Count(rows) do
		local row = At(rows, index)
		result[#result + 1] = {
			id = tostring(Value(row, "application_id") or ""),
			accountId = tostring(Value(row, "account_id") or ""),
			citizenId = tostring(Value(row, "citizen_id") or ""),
			displayName = tostring(Value(row, "display_name") or ""),
			platform = tostring(Value(row, "platform") or ""),
			channelUrl = tostring(Value(row, "channel_url") or ""),
			audience = tonumber(Value(row, "audience") or 0) or 0,
			pitch = tostring(Value(row, "pitch") or ""),
			status = tostring(Value(row, "status") or "pending"),
			reviewNote = tostring(Value(row, "review_note") or ""),
			createdAt = tonumber(Value(row, "created_at") or 0) or 0,
			updatedAt = tonumber(Value(row, "updated_at") or 0) or 0,
		}
	end
	return result
end

function DB.UpdatePartnerApplication(applicationId, expectedStatus, status, reviewNote)
	return Execute([[UPDATE creatorlink_partner_applications SET status = ?, review_note = ?, updated_at = ?
		WHERE application_id = ? AND status = ?]], {
		tostring(status or ""), tostring(reviewNote or ""), os.time(),
		tostring(applicationId or ""), tostring(expectedStatus or ""),
	})
end

function DB.SeedPartners(partners)
	local now = os.time()
	for _, partner in ipairs(partners or {}) do
		RequireExecute([[INSERT OR IGNORE INTO creatorlink_partners (
			partner_id, owner_account_id, code, display_name, channel, description,
			status, featured, commission_bps, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
			tostring(partner.Id or ""), tostring(partner.OwnerAccountId or ""), string.upper(tostring(partner.Code or "")),
			tostring(partner.DisplayName or partner.Id or "Creator"), tostring(partner.Channel or ""),
			tostring(partner.Description or ""), tostring(partner.Status or "active"), partner.Featured == true and 1 or 0,
			math.max(0, math.floor(tonumber(partner.CommissionBps) or 0)), now, now,
		})
		RequireExecute([[UPDATE creatorlink_partners SET owner_account_id = ?, code = ?, display_name = ?, channel = ?,
			description = ?, status = ?, featured = ?, commission_bps = ?, updated_at = ? WHERE partner_id = ?]], {
			tostring(partner.OwnerAccountId or ""), string.upper(tostring(partner.Code or "")),
			tostring(partner.DisplayName or partner.Id or "Creator"), tostring(partner.Channel or ""),
			tostring(partner.Description or ""), tostring(partner.Status or "active"), partner.Featured == true and 1 or 0,
			math.max(0, math.floor(tonumber(partner.CommissionBps) or 0)), now, tostring(partner.Id or ""),
		})
	end
end

function DB.BackfillEntitlements(rewards)
	local firstDiscountDays = math.max(0, math.floor(tonumber(rewards and rewards.First and rewards.First.ShopDiscountDays) or 0))
	local repeatDiscountDays = math.max(0, math.floor(tonumber(rewards and rewards.Repeat and rewards.Repeat.ShopDiscountDays) or 0))
	local now = os.time()
	RequireExecute([[INSERT OR IGNORE INTO creatorlink_entitlements (
		entitlement_id, account_id, citizen_id, claim_id, entitlement_type, value_integer,
		starts_at, expires_at, status, metadata, created_at, updated_at
	) SELECT claim_id || ':premium', account_id, citizen_id, claim_id, 'premium', premium_days,
		granted_at, granted_at + (premium_days * 86400), 'active', '', granted_at, ?
		FROM creatorlink_reward_claims WHERE status = 'granted' AND premium_days > 0]], { now })
	RequireExecute([[INSERT OR IGNORE INTO creatorlink_entitlements (
		entitlement_id, account_id, citizen_id, claim_id, entitlement_type, value_integer,
		starts_at, expires_at, status, metadata, created_at, updated_at
	) SELECT claim_id || ':shop_discount', account_id, citizen_id, claim_id, 'shop_discount', discount_bps,
		granted_at, granted_at + ((CASE WHEN reward_type = 'first' THEN ? ELSE ? END) * 86400),
		'active', '', granted_at, ? FROM creatorlink_reward_claims
		WHERE status = 'granted' AND discount_bps > 0]], { firstDiscountDays, repeatDiscountDays, now })
end

function DB.GetPartnerByCode(code)
	return Row(First(Select("SELECT * FROM creatorlink_partners WHERE code = ? AND status = 'active' LIMIT 1", { string.upper(tostring(code or "")) })))
end

function DB.GetPartnerByCodeAny(code)
	return Row(First(Select("SELECT * FROM creatorlink_partners WHERE code = ? LIMIT 1", { string.upper(tostring(code or "")) })))
end

function DB.GetPartnerByOwner(accountId)
	return Row(First(Select("SELECT * FROM creatorlink_partners WHERE owner_account_id = ? AND status = 'active' LIMIT 1", { tostring(accountId or "") })))
end

function DB.GetPartnerByOwnerAny(accountId)
	return Row(First(Select("SELECT * FROM creatorlink_partners WHERE owner_account_id = ? ORDER BY created_at DESC LIMIT 1", { tostring(accountId or "") })))
end

function DB.GetPartner(partnerId)
	return Row(First(Select("SELECT * FROM creatorlink_partners WHERE partner_id = ? LIMIT 1", { tostring(partnerId or "") })))
end

function DB.CreatePartner(partner)
	return Execute([[INSERT INTO creatorlink_partners (
		partner_id, owner_account_id, code, display_name, channel, description,
		status, featured, level, commission_bps, reputation, credits, momentum, created_at, updated_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, 0, 0, 0, ?, ?)]], {
		partner.partnerId, partner.ownerAccountId, partner.code, partner.displayName,
		partner.channel, partner.description, partner.status or "pending_activation",
		partner.featured == true and 1 or 0, math.max(0, math.floor(tonumber(partner.commissionBps) or 0)),
		partner.createdAt, partner.createdAt,
	})
end

function DB.UpdatePartnerStatus(partnerId, expectedStatus, status)
	return Execute([[UPDATE creatorlink_partners SET status = ?, updated_at = ?
		WHERE partner_id = ? AND status = ?]], {
		tostring(status or ""), os.time(), tostring(partnerId or ""), tostring(expectedStatus or ""),
	})
end

function DB.ListPartners()
	local rows = Select("SELECT * FROM creatorlink_partners WHERE status = 'active' ORDER BY featured DESC, display_name ASC", {})
	local result = {}
	for index = 1, Count(rows) do result[#result + 1] = Row(At(rows, index)) end
	return result
end

function DB.GetLink(accountId)
	local row = First(Select([[SELECT l.*, p.display_name, p.channel, p.description, p.status AS partner_status,
		p.level, p.commission_bps, c.status AS reward_claim_status
		FROM creatorlink_player_links l JOIN creatorlink_partners p ON p.partner_id = l.partner_id
		JOIN creatorlink_reward_claims c ON c.claim_id = l.reward_claim_id
		WHERE l.account_id = ? LIMIT 1]], { tostring(accountId or "") }))
	if not row then return nil end
	return {
		accountId = tostring(Value(row, "account_id") or ""), citizenId = tostring(Value(row, "citizen_id") or ""),
		partnerId = tostring(Value(row, "partner_id") or ""), code = tostring(Value(row, "code") or ""),
		partnerName = tostring(Value(row, "display_name") or ""), channel = tostring(Value(row, "channel") or ""),
		description = tostring(Value(row, "description") or ""), level = tonumber(Value(row, "level") or 1) or 1,
		partnerStatus = tostring(Value(row, "partner_status") or "disabled"),
		rewardClaimStatus = tostring(Value(row, "reward_claim_status") or ""),
		commissionBps = tonumber(Value(row, "commission_bps") or 0) or 0,
		cycleNumber = tonumber(Value(row, "cycle_number") or 1) or 1,
		activatedAt = tonumber(Value(row, "activated_at") or 0) or 0,
		expiresAt = tonumber(Value(row, "expires_at") or 0) or 0,
		rewardClaimId = tostring(Value(row, "reward_claim_id") or ""),
		updatedAt = tonumber(Value(row, "updated_at") or 0) or 0,
	}
end

function DB.CountClaims(accountId)
	local row = First(Select("SELECT COUNT(*) AS total FROM creatorlink_reward_claims WHERE account_id = ? AND status = 'granted'", { tostring(accountId or "") }))
	return tonumber(Value(row, "total") or 0) or 0
end

function DB.GetClaimByIdempotencyKey(idempotencyKey)
	local row = First(Select([[SELECT claim_id, idempotency_key, account_id, status, error, created_at, granted_at
		FROM creatorlink_reward_claims WHERE idempotency_key = ? LIMIT 1]], { tostring(idempotencyKey or "") }))
	if not row then return nil end
	return {
		claimId = tostring(Value(row, "claim_id") or ""),
		idempotencyKey = tostring(Value(row, "idempotency_key") or ""),
		accountId = tostring(Value(row, "account_id") or ""),
		status = tostring(Value(row, "status") or ""),
		error = tostring(Value(row, "error") or ""),
		createdAt = tonumber(Value(row, "created_at") or 0) or 0,
		grantedAt = tonumber(Value(row, "granted_at") or 0) or 0,
	}
end

function DB.DeleteFailedClaim(claimId)
	return Execute("DELETE FROM creatorlink_reward_claims WHERE claim_id = ? AND status = 'failed'", { tostring(claimId or "") })
end

function DB.CreateClaim(claim)
	return Execute([[INSERT INTO creatorlink_reward_claims (
		claim_id, idempotency_key, account_id, citizen_id, partner_id, cycle_number, reward_type,
		cash_amount, premium_days, discount_bps, status, error, created_at, granted_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', ?, 0)]], {
		claim.claimId, claim.idempotencyKey, claim.accountId, claim.citizenId, claim.partnerId,
		claim.cycleNumber, claim.rewardType, claim.cashAmount, claim.premiumDays, claim.discountBps,
		"processing", claim.createdAt,
	})
end

function DB.FailClaim(claimId, err)
	return Execute("UPDATE creatorlink_reward_claims SET status = 'failed', error = ? WHERE claim_id = ?", { tostring(err or "reward_failed"), tostring(claimId) })
end

function DB.ReviewClaim(claimId, err)
	return Execute("UPDATE creatorlink_reward_claims SET status = 'review_required', error = ? WHERE claim_id = ?", {
		tostring(err or "manual_review_required"), tostring(claimId),
	})
end

function DB.GrantClaim(claimId, grantedAt)
	return Execute("UPDATE creatorlink_reward_claims SET status = 'granted', granted_at = ?, error = '' WHERE claim_id = ?", { grantedAt, tostring(claimId) })
end

function DB.CreateEntitlement(entitlement)
	return Execute([[INSERT OR IGNORE INTO creatorlink_entitlements (
		entitlement_id, account_id, citizen_id, claim_id, entitlement_type, value_integer,
		starts_at, expires_at, status, metadata, created_at, updated_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?)]], {
		entitlement.id, entitlement.accountId, entitlement.citizenId, entitlement.claimId,
		entitlement.type, entitlement.value, entitlement.startsAt, entitlement.expiresAt,
		tostring(entitlement.metadata or ""), entitlement.createdAt, entitlement.createdAt,
	})
end

function DB.ListActiveEntitlements(accountId, now)
	local rows = Select([[SELECT e.entitlement_id, e.claim_id, e.entitlement_type, e.value_integer, e.starts_at, e.expires_at
		FROM creatorlink_entitlements e JOIN creatorlink_reward_claims c ON c.claim_id = e.claim_id
		WHERE e.account_id = ? AND e.status = 'active' AND c.status = 'granted'
		AND (e.expires_at = 0 OR e.expires_at > ?) ORDER BY e.created_at DESC]], { tostring(accountId or ""), tonumber(now) or os.time() })
	local result = {}
	for index = 1, Count(rows) do
		local row = At(rows, index)
		result[#result + 1] = {
			id = tostring(Value(row, "entitlement_id") or ""),
			claimId = tostring(Value(row, "claim_id") or ""),
			type = tostring(Value(row, "entitlement_type") or ""),
			value = tonumber(Value(row, "value_integer") or 0) or 0,
			startsAt = tonumber(Value(row, "starts_at") or 0) or 0,
			expiresAt = tonumber(Value(row, "expires_at") or 0) or 0,
		}
	end
	return result
end

function DB.GetActiveEntitlement(accountId, entitlementType, now)
	local row = First(Select([[SELECT e.entitlement_id, e.claim_id, e.entitlement_type, e.value_integer, e.starts_at, e.expires_at
		FROM creatorlink_entitlements e JOIN creatorlink_reward_claims c ON c.claim_id = e.claim_id
		WHERE e.account_id = ? AND e.entitlement_type = ? AND e.status = 'active' AND c.status = 'granted'
		AND (e.expires_at = 0 OR e.expires_at > ?)
		ORDER BY CASE WHEN e.expires_at = 0 THEN 1 ELSE 0 END DESC, e.expires_at DESC LIMIT 1]], {
		tostring(accountId or ""), tostring(entitlementType or ""), tonumber(now) or os.time(),
	}))
	if not row then return nil end
	return {
		id = tostring(Value(row, "entitlement_id") or ""),
		claimId = tostring(Value(row, "claim_id") or ""),
		type = tostring(Value(row, "entitlement_type") or ""),
		value = tonumber(Value(row, "value_integer") or 0) or 0,
		startsAt = tonumber(Value(row, "starts_at") or 0) or 0,
		expiresAt = tonumber(Value(row, "expires_at") or 0) or 0,
	}
end

function DB.DeleteEntitlementsForClaim(claimId)
	return Execute("DELETE FROM creatorlink_entitlements WHERE claim_id = ?", { tostring(claimId or "") })
end

function DB.CreateBenefitRequest(request)
	return Execute([[INSERT INTO creatorlink_benefit_requests (
		request_id, partner_id, owner_account_id, benefit_id, benefit_label, cost_credits,
		status, note, created_at, updated_at
	) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)]], {
		request.id, request.partnerId, request.ownerAccountId, request.benefitId,
		request.benefitLabel, request.costCredits, tostring(request.note or ""),
		request.createdAt, request.createdAt,
	})
end

function DB.HasOpenBenefitRequest(partnerId, benefitId)
	local row = First(Select([[SELECT request_id FROM creatorlink_benefit_requests
		WHERE partner_id = ? AND benefit_id = ? AND status IN ('pending', 'approved') LIMIT 1]], {
		tostring(partnerId or ""), tostring(benefitId or ""),
	}))
	return row ~= nil
end

function DB.GetBenefitRequest(requestId)
	local row = First(Select([[SELECT request_id, partner_id, owner_account_id, benefit_id, benefit_label,
		cost_credits, status, note, review_note, created_at, updated_at FROM creatorlink_benefit_requests
		WHERE request_id = ? LIMIT 1]], { tostring(requestId or "") }))
	if not row then return nil end
	return {
		id = tostring(Value(row, "request_id") or ""),
		partnerId = tostring(Value(row, "partner_id") or ""),
		ownerAccountId = tostring(Value(row, "owner_account_id") or ""),
		benefitId = tostring(Value(row, "benefit_id") or ""),
		label = tostring(Value(row, "benefit_label") or ""),
		costCredits = tonumber(Value(row, "cost_credits") or 0) or 0,
		status = tostring(Value(row, "status") or "pending"),
		note = tostring(Value(row, "note") or ""),
		reviewNote = tostring(Value(row, "review_note") or ""),
		createdAt = tonumber(Value(row, "created_at") or 0) or 0,
		updatedAt = tonumber(Value(row, "updated_at") or 0) or 0,
	}
end

function DB.UpdateBenefitRequest(requestId, expectedStatus, status, reviewNote)
	return Execute([[UPDATE creatorlink_benefit_requests SET status = ?, review_note = ?, updated_at = ?
		WHERE request_id = ? AND status = ?]], {
		tostring(status or "pending"), tostring(reviewNote or ""), os.time(),
		tostring(requestId or ""), tostring(expectedStatus or ""),
	})
end


function DB.CancelBenefitRequest(requestId)
	return Execute([[UPDATE creatorlink_benefit_requests SET status = 'cancelled', updated_at = ?
		WHERE request_id = ? AND status = 'pending']], { os.time(), tostring(requestId or "") })
end

function DB.ListBenefitRequests(partnerId, limit)
	local safeLimit = math.max(1, math.min(20, math.floor(tonumber(limit) or 8)))
	local rows = Select([[SELECT request_id, benefit_id, benefit_label, cost_credits, status, note, review_note, created_at, updated_at
		FROM creatorlink_benefit_requests WHERE partner_id = ? ORDER BY created_at DESC LIMIT ]] .. tostring(safeLimit), {
		tostring(partnerId or ""),
	})
	local result = {}
	for index = 1, Count(rows) do
		local row = At(rows, index)
		result[#result + 1] = {
			id = tostring(Value(row, "request_id") or ""),
			benefitId = tostring(Value(row, "benefit_id") or ""),
			label = tostring(Value(row, "benefit_label") or ""),
			costCredits = tonumber(Value(row, "cost_credits") or 0) or 0,
			status = tostring(Value(row, "status") or "pending"),
			note = tostring(Value(row, "note") or ""),
			reviewNote = tostring(Value(row, "review_note") or ""),
			createdAt = tonumber(Value(row, "created_at") or 0) or 0,
			updatedAt = tonumber(Value(row, "updated_at") or 0) or 0,
		}
	end
	return result
end

function DB.UpsertLink(link)
	return Execute([[INSERT INTO creatorlink_player_links (
		account_id, citizen_id, partner_id, code, cycle_number, activated_at, expires_at, reward_claim_id, updated_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	ON CONFLICT(account_id) DO UPDATE SET citizen_id = excluded.citizen_id, partner_id = excluded.partner_id,
		code = excluded.code, cycle_number = excluded.cycle_number, activated_at = excluded.activated_at,
		expires_at = excluded.expires_at, reward_claim_id = excluded.reward_claim_id, updated_at = excluded.updated_at]], {
		link.accountId, link.citizenId, link.partnerId, link.code, link.cycleNumber,
		link.activatedAt, link.expiresAt, link.rewardClaimId, link.updatedAt,
	})
end

function DB.DeleteLink(accountId)
	return Execute("DELETE FROM creatorlink_player_links WHERE account_id = ?", { tostring(accountId or "") })
end

function DB.AddProgress(partnerId, accountId, eventType, progress)
	local now = os.time()
	local entryId = string.format("point_%d_%06d", now, math.random(0, 999999))
	local reputation = math.floor(tonumber(progress.Reputation) or 0)
	local credits = math.floor(tonumber(progress.Credits) or 0)
	local momentum = math.floor(tonumber(progress.Momentum) or 0)
	RequireExecute([[INSERT INTO creatorlink_points_ledger (entry_id, partner_id, account_id, event_type, reputation, credits, momentum, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)]], { entryId, partnerId, accountId, eventType, reputation, credits, momentum, now })
	RequireExecute([[UPDATE creatorlink_partners SET reputation = MAX(0, reputation + ?), credits = MAX(0, credits + ?),
		momentum = MAX(0, MIN(1000, momentum + ?)), updated_at = ? WHERE partner_id = ?]], {
		reputation, credits, momentum, now, partnerId,
	})
	return true
end

function DB.PartnerDashboard(partnerId, now)
	local partner = DB.GetPartner(partnerId)
	if not partner then return nil end
	local activeStats = First(Select([[SELECT COUNT(*) AS active_players
		FROM creatorlink_player_links l JOIN creatorlink_reward_claims c ON c.claim_id = l.reward_claim_id
		WHERE l.partner_id = ? AND l.expires_at > ? AND c.status = 'granted']], { partnerId, now }))
	local activationStats = First(Select([[SELECT
		SUM(CASE WHEN reward_type = 'first' THEN 1 ELSE 0 END) AS first_activations,
		SUM(CASE WHEN reward_type = 'repeat' THEN 1 ELSE 0 END) AS repeat_activations
		FROM creatorlink_reward_claims WHERE partner_id = ? AND status = 'granted']], { partnerId }))
	local commission = First(Select([[SELECT
		SUM(CASE WHEN status = 'pending' AND currency = 'LIX' THEN commission_lix ELSE 0 END) AS pending_commission,
		SUM(CASE WHEN status = 'settled' AND currency = 'LIX' THEN commission_lix ELSE 0 END) AS approved_commission
		FROM creatorlink_transactions WHERE partner_id = ?]], { partnerId }))
	local benefitStats = First(Select([[SELECT
		SUM(CASE WHEN status IN ('pending', 'approved') THEN cost_credits ELSE 0 END) AS reserved_credits,
		SUM(CASE WHEN status = 'fulfilled' THEN cost_credits ELSE 0 END) AS spent_credits,
		SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_requests
		FROM creatorlink_benefit_requests WHERE partner_id = ?]], { partnerId }))
	partner.activePlayers = tonumber(Value(activeStats, "active_players") or 0) or 0
	partner.firstActivations = tonumber(Value(activationStats, "first_activations") or 0) or 0
	partner.repeatActivations = tonumber(Value(activationStats, "repeat_activations") or 0) or 0
	partner.pendingCommission = tonumber(Value(commission, "pending_commission") or 0) or 0
	partner.approvedCommission = tonumber(Value(commission, "approved_commission") or 0) or 0
	partner.reservedCredits = math.max(0, tonumber(Value(benefitStats, "reserved_credits") or 0) or 0)
	partner.spentCredits = math.max(0, tonumber(Value(benefitStats, "spent_credits") or 0) or 0)
	partner.availableCredits = math.max(0, partner.credits - partner.reservedCredits - partner.spentCredits)
	partner.pendingBenefitRequests = math.max(0, tonumber(Value(benefitStats, "pending_requests") or 0) or 0)
	return partner
end

function DB.LatestReward(accountId)
	local row = First(Select([[SELECT claim_id, reward_type, cash_amount, premium_days, discount_bps, granted_at
		FROM creatorlink_reward_claims WHERE account_id = ? AND status = 'granted' ORDER BY granted_at DESC LIMIT 1]], { accountId }))
	if not row then return nil end
	return {
		claimId = tostring(Value(row, "claim_id") or ""),
		type = tostring(Value(row, "reward_type") or ""), cash = tonumber(Value(row, "cash_amount") or 0) or 0,
		premiumDays = tonumber(Value(row, "premium_days") or 0) or 0,
		discountBps = tonumber(Value(row, "discount_bps") or 0) or 0,
		grantedAt = tonumber(Value(row, "granted_at") or 0) or 0,
	}
end

function DB.RecordTransaction(transaction)
	return Execute([[INSERT OR IGNORE INTO creatorlink_transactions (
		transaction_id, account_id, partner_id, partner_code, commission_bps, amount_minor,
		commission_minor, amount_lix, helix_fee_lix, server_net_lix, commission_lix,
		currency, status, created_at, updated_at
	) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
		transaction.id, transaction.accountId, transaction.partnerId, transaction.partnerCode,
		transaction.commissionBps, transaction.amountLix, transaction.commissionLix,
		transaction.amountLix, transaction.helixFeeLix, transaction.serverNetLix, transaction.commissionLix,
		transaction.currency, transaction.status, transaction.createdAt, transaction.createdAt,
	})
end

function DB.GetTransaction(transactionId)
	local row = First(Select("SELECT * FROM creatorlink_transactions WHERE transaction_id = ? LIMIT 1", { tostring(transactionId or "") }))
	if not row then return nil end
	return {
		id = tostring(Value(row, "transaction_id") or ""),
		accountId = tostring(Value(row, "account_id") or ""),
		partnerId = tostring(Value(row, "partner_id") or ""),
		partnerCode = tostring(Value(row, "partner_code") or ""),
		commissionBps = tonumber(Value(row, "commission_bps") or 0) or 0,
		amountLix = tonumber(Value(row, "amount_lix") or 0) or 0,
		helixFeeLix = tonumber(Value(row, "helix_fee_lix") or 0) or 0,
		serverNetLix = tonumber(Value(row, "server_net_lix") or 0) or 0,
		commissionLix = tonumber(Value(row, "commission_lix") or 0) or 0,
		currency = tostring(Value(row, "currency") or "LIX"),
		status = tostring(Value(row, "status") or ""),
		createdAt = tonumber(Value(row, "created_at") or 0) or 0,
		updatedAt = tonumber(Value(row, "updated_at") or 0) or 0,
	}
end

function DB.UpdateTransaction(transactionId, status)
	return Execute("UPDATE creatorlink_transactions SET status = ?, updated_at = ? WHERE transaction_id = ?", { status, os.time(), transactionId })
end

function DB.ListPlayerCycles(accountId, limit)
	local safeLimit = math.max(1, math.min(20, math.floor(tonumber(limit) or 8)))
	local rows = Select([[SELECT c.claim_id, c.reward_type, c.cash_amount, c.premium_days, c.discount_bps,
		c.granted_at, c.status, p.code, p.display_name
		FROM creatorlink_reward_claims c LEFT JOIN creatorlink_partners p ON p.partner_id = c.partner_id
		WHERE c.account_id = ? AND c.status = 'granted' ORDER BY c.granted_at DESC LIMIT ]] .. tostring(safeLimit), {
		tostring(accountId or ""),
	})
	local result = {}
	for index = 1, Count(rows) do
		local row = At(rows, index)
		result[#result + 1] = {
			id = tostring(Value(row, "claim_id") or ""),
			type = tostring(Value(row, "reward_type") or ""),
			code = tostring(Value(row, "code") or ""),
			partnerName = tostring(Value(row, "display_name") or ""),
			cash = tonumber(Value(row, "cash_amount") or 0) or 0,
			premiumDays = tonumber(Value(row, "premium_days") or 0) or 0,
			discountBps = tonumber(Value(row, "discount_bps") or 0) or 0,
			grantedAt = tonumber(Value(row, "granted_at") or 0) or 0,
		}
	end
	return result
end

function DB.ListPartnerActivity(partnerId, limit)
	local safeLimit = math.max(1, math.min(30, math.floor(tonumber(limit) or 10)))
	local rows = Select([[SELECT entry_id, event_type, reputation, credits, momentum, created_at
		FROM creatorlink_points_ledger WHERE partner_id = ? ORDER BY created_at DESC LIMIT ]] .. tostring(safeLimit), {
		tostring(partnerId or ""),
	})
	local result = {}
	for index = 1, Count(rows) do
		local row = At(rows, index)
		result[#result + 1] = {
			id = tostring(Value(row, "entry_id") or ""),
			type = tostring(Value(row, "event_type") or ""),
			reputation = tonumber(Value(row, "reputation") or 0) or 0,
			credits = tonumber(Value(row, "credits") or 0) or 0,
			momentum = tonumber(Value(row, "momentum") or 0) or 0,
			createdAt = tonumber(Value(row, "created_at") or 0) or 0,
		}
	end
	return result
end

function DB.ListPartnerTransactions(partnerId, limit)
	local safeLimit = math.max(1, math.min(30, math.floor(tonumber(limit) or 10)))
	local rows = Select([[SELECT transaction_id, amount_lix, helix_fee_lix, server_net_lix, commission_lix, currency, status, created_at
		FROM creatorlink_transactions WHERE partner_id = ? AND currency = 'LIX' ORDER BY created_at DESC LIMIT ]] .. tostring(safeLimit), {
		tostring(partnerId or ""),
	})
	local result = {}
	for index = 1, Count(rows) do
		local row = At(rows, index)
		result[#result + 1] = {
			id = tostring(Value(row, "transaction_id") or ""),
			amountLix = tonumber(Value(row, "amount_lix") or 0) or 0,
			helixFeeLix = tonumber(Value(row, "helix_fee_lix") or 0) or 0,
			serverNetLix = tonumber(Value(row, "server_net_lix") or 0) or 0,
			commissionLix = tonumber(Value(row, "commission_lix") or 0) or 0,
			currency = tostring(Value(row, "currency") or "LIX"),
			status = tostring(Value(row, "status") or ""),
			createdAt = tonumber(Value(row, "created_at") or 0) or 0,
		}
	end
	return result
end

return DB
