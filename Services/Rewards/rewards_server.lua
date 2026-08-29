-- scripts/m-phone/Extras/rewards_server.lua

print("[m-phone][server] Rewards server module LOADED")

-- NOTE:
-- This module is a simple server-side payout bridge for testing and future job payouts.
-- It relies on the legacy DB bridge, which delegates credits to the configured bank provider.
-- HELIX: no GetCurrentResourceName() concept. We use explicit audit tags in meta.

local SYSTEM_ACTOR_ID = "bank:system"
local DEFAULT_KIND = "salary"
local DEFAULT_SYSTEM_TAG = "m-phone:rewards"
local Shared = require("Services.Rewards.rewards_server_shared")
local EventShared = require("server_shared")

local function GetCore()
	return _G.MPhone
end

local function GetDB()
	local Core = GetCore()
	return Core and Core.DB or nil
end

local function NowMsSafe()
	return Shared.NowMsSafe()
end

local function TestMutationsEnabled()
	return Debug == true
		and Config
		and type(Config.Developer) == "table"
		and Config.Developer.AllowTestMutations == true
end

local function NotifyClient(src, payload)
	Shared.NotifyClient(src, payload)
end

local function LogInfo(msg)
	Shared.LogInfo(msg)
end

local function LogWarn(msg)
	Shared.LogWarn(msg)
end

local function LogErr(msg)
	Shared.LogErr(msg)
end

local function NormalizeAmount(v)
	return Shared.NormalizeAmount(v)
end

local function NormalizeText(v, fallback)
	return Shared.NormalizeText(v, fallback)
end

local function CreditByPid(pid, amount, reference, kind, meta, ensureAccount)
	local DB = GetDB()
	if not DB or not DB.CreditPlayer then
		LogErr("DB.CreditPlayer missing")
		return { ok = false, error = "db_missing_credit" }
	end

	local toPid = tostring(pid or "")
	local amt = NormalizeAmount(amount)
	local ref = NormalizeText(reference, "Payout")
	local k = NormalizeText(kind, DEFAULT_KIND)

	if toPid == "" then return { ok = false, error = "player_not_found" } end
	if amt <= 0 then return { ok = false, error = "invalid_amount" } end
	if ref == "" or #ref < 2 then return { ok = false, error = "invalid_reference" } end

	meta = type(meta) == "table" and meta or {}

	-- Audit tags (HELIX-safe)
	meta.system = meta.system ~= nil and tostring(meta.system) or DEFAULT_SYSTEM_TAG
	meta.origin = meta.origin ~= nil and tostring(meta.origin) or "server_payout"
	meta.reason = meta.reason ~= nil and tostring(meta.reason) or k
	meta.source = meta.source ~= nil and tostring(meta.source) or "server"

	-- Deterministic identifiers for grouping and investigation
	if meta.requestId == nil or tostring(meta.requestId) == "" then
		meta.requestId = ("credit|%s|%s"):format(tostring(NowMsSafe()), toPid)
	end
	if meta.groupId == nil or tostring(meta.groupId) == "" then
		meta.groupId = ("income|%s|%s"):format(tostring(NowMsSafe()), toPid)
	end

	-- Actor/peer for ledger context
	meta.actorId = meta.actorId ~= nil and tostring(meta.actorId) or SYSTEM_ACTOR_ID
	meta.peerId = meta.peerId ~= nil and tostring(meta.peerId) or SYSTEM_ACTOR_ID

	local res = DB.CreditPlayer(toPid, amt, k, ref, meta, ensureAccount == true)
	return res or { ok = false, error = "unknown" }
end

local function CreditToSource(source, amount, reference, kind, meta, ensureAccount)
	local Core = GetCore()
	if not Core or not Core.GetPlayerId then
		LogErr("Core.GetPlayerId missing")
		return { ok = false, error = "core_missing_playerid" }
	end

	local pid = tostring(Core.GetPlayerId(source) or "")
	if pid == "" then
		return { ok = false, error = "player_not_found" }
	end

	return CreditByPid(pid, amount, reference, kind, meta, ensureAccount)
end

-- Expose a simple server API for other server scripts
do
	local Core = GetCore()
	if Core then
		Core.Rewards = Core.Rewards or {}

		function Core.Rewards.PayPlayer(pid, amount, reference, kind, meta, ensureAccount)
			return CreditByPid(pid, amount, reference, kind, meta, ensureAccount)
		end

		function Core.Rewards.PaySource(source, amount, reference, kind, meta, ensureAccount)
			return CreditToSource(source, amount, reference, kind, meta, ensureAccount)
		end
	end
end

-- =========================================================
-- TEST BRIDGE (client calls -> server always tries to pay)
-- You will delete this later when jobs/contracts are wired.
-- =========================================================
RegisterServerEvent("m-phone:rewards:testPayout", function(a, b)
	local source, data = EventShared.ResolveControllerAndPayload(a, b)
	if not TestMutationsEnabled() then
		LogWarn("testPayout rejected: developer mutations disabled")
		return
	end
	LogInfo(("testPayout IN source=%s type=%s"):format(tostring(source), tostring(type(data))))

	if type(data) ~= "table" then
		LogWarn("testPayout bad payload")
		return
	end

	local amount = NormalizeAmount(data.amount)
	local reference = NormalizeText(data.reference, "Test payout")
	local kind = NormalizeText(data.kind or data.txType, DEFAULT_KIND)

	-- Money formatter (cents -> "0.00")
	local function FormatMoneyFromCents(cents)
		return Shared.FormatMoneyFromCents(cents)
	end

	if amount <= 0 then
		LogWarn("testPayout invalid amount")
		NotifyClient(source, {
			kind = "bank",
			code = "invalid_amount",
			title = "Payment failed",
			message = "Invalid amount, payment not processed.",

			amount = amount,
			amountText = FormatMoneyFromCents(amount),

			reference = reference
		})
		return
	end

	local reqId = NormalizeText(data.requestId, ("testpay|" .. tostring(NowMsSafe())))

	local meta = type(data.meta) == "table" and data.meta or {}
	meta.debug = true
	meta.system = meta.system or DEFAULT_SYSTEM_TAG
	meta.origin = meta.origin or "test_bridge"
	meta.reason = meta.reason or "test_payout"
	meta.details = meta.details or data.loc
	meta.requestId = reqId
	meta.groupId = meta.groupId or ("income|" .. reqId)

	-- IMPORTANT:
	-- ensureAccount = false by default.
	-- If player has no bank account, ledger will return "no_bank_account".
	local res = CreditToSource(source, amount, reference, kind, meta, false)

	LogInfo(("testPayout OUT ok=%s err=%s txId=%s"):format(
		tostring(res and res.ok),
		tostring(res and res.error),
		tostring(res and res.txId)
	))

	if res and res.ok then
		NotifyClient(source, {
			kind = "bank",
			code = "credited",
			title = "Payment received",
			message = ("Credited $%s."):format(FormatMoneyFromCents(amount)),

			amount = amount,
			amountText = FormatMoneyFromCents(amount),

			reference = reference,
			txId = res.txId,
			groupId = res.groupId,

			-- NEW: for BankApp notifications (still cents)
			balanceBefore = res.balanceBefore,
			balanceAfter = res.balanceAfter,

			-- NEW: formatted for UI text (dollars)
			balanceBeforeText = FormatMoneyFromCents(res.balanceBefore),
			balanceAfterText = FormatMoneyFromCents(res.balanceAfter),
		})
	else
		local err = tostring(res and res.error or "unknown_error")

		local msg = "Payment failed."
		if err == "no_bank_account" then
			msg = ("No bank account found. $%s was not credited."):format(FormatMoneyFromCents(amount))
		elseif err == "recipient_locked" then
			msg = "Bank account is locked. Payment not credited."
		elseif err == "db_update_failed" then
			msg = "Database update failed. Payment not credited."
		end

		NotifyClient(source, {
			kind = "bank",
			code = err,
			title = "Payment failed",
			message = msg,

			amount = amount,
			amountText = FormatMoneyFromCents(amount),

			reference = reference
		})
	end
end)


-- =========================================================
-- TEST DEBIT (client calls -> server tries to charge)
-- Uses the legacy DB bridge, which delegates debits to the configured bank provider.
-- =========================================================
RegisterServerEvent("m-phone:bank:testDebit", function(a, b)
	local source, data = EventShared.ResolveControllerAndPayload(a, b)
	if not TestMutationsEnabled() then
		LogWarn("testDebit rejected: developer mutations disabled")
		return
	end
	LogInfo(("testDebit IN source=%s type=%s"):format(tostring(source), tostring(type(data))))

	if type(data) ~= "table" then
		LogWarn("testDebit bad payload")
		NotifyClient(source, {
			kind = "bank",
			code = "invalid_payload",
			title = "Charge failed",
			message = "Invalid payload, charge not processed.",
		})
		return
	end

	local amount = NormalizeAmount(data.amount)
	local reference = NormalizeText(data.reference, "Test debit")
	local kind = NormalizeText(data.kind or data.txType, "expense") -- or "shop_purchase"

	if amount <= 0 then
		LogWarn("testDebit invalid amount")
		NotifyClient(source, {
			kind = "bank",
			code = "invalid_amount",
			title = "Charge failed",
			message = "Invalid amount, charge not processed.",
			amount = amount,
			reference = reference
		})
		return
	end

	-- mock "conditions" check (імітація: доступ/рівень/права/кд/тощо)
	-- клієнт може передати flag, але сервер сам вирішує
	local allow = true
	if data.requireFlag == true then
		allow = (data.flag == true)
	end

	if not allow then
		NotifyClient(source, {
			kind = "bank",
			code = "conditions_failed",
			title = "Charge denied",
			message = "Conditions not met. Charge not processed.",
			amount = amount,
			reference = reference
		})
		return
	end

	local reqId = NormalizeText(data.requestId, ("testdebit|" .. tostring(NowMsSafe())))

	local meta = type(data.meta) == "table" and data.meta or {}
	meta.debug = true
	meta.system = meta.system or DEFAULT_SYSTEM_TAG
	meta.origin = meta.origin or "test_debit_bridge"
	meta.reason = meta.reason or "test_debit"
	meta.details = meta.details or data.loc
	meta.requestId = reqId
	meta.groupId = meta.groupId or ("expense|" .. reqId)

	-- Actor/peer for ledger context
	meta.actorId = meta.actorId ~= nil and tostring(meta.actorId) or (function()
		local Core = GetCore()
		if Core and Core.GetPlayerId then
			return tostring(Core.GetPlayerId(source) or SYSTEM_ACTOR_ID)
		end
		return SYSTEM_ACTOR_ID
	end)()

	meta.peerId = meta.peerId ~= nil and tostring(meta.peerId) or "bank:merchant:test"

	-- Resolve pid
	local Core = GetCore()
	if not Core or not Core.GetPlayerId then
		LogErr("Core.GetPlayerId missing")
		NotifyClient(source, {
			kind = "bank",
			code = "core_missing_playerid",
			title = "Charge failed",
			message = "Core API missing. Charge not processed.",
			amount = amount,
			reference = reference
		})
		return
	end

	local pid = tostring(Core.GetPlayerId(source) or "")
	if pid == "" then
		NotifyClient(source, {
			kind = "bank",
			code = "player_not_found",
			title = "Charge failed",
			message = "Player not found.",
			amount = amount,
			reference = reference
		})
		return
	end

	-- Debit via DB
	local DB = GetDB()
	if not DB or not DB.DebitPlayer then
		LogErr("DB.DebitPlayer missing")
		NotifyClient(source, {
			kind = "bank",
			code = "db_missing_debit",
			title = "Charge failed",
			message = "Bank debit is unavailable.",
			amount = amount,
			reference = reference
		})
		return
	end

	local res = DB.DebitPlayer(pid, amount, kind, reference, meta)

	LogInfo(("testDebit OUT ok=%s err=%s txId=%s"):format(
		tostring(res and res.ok),
		tostring(res and res.error),
		tostring(res and res.txId)
	))

	if res and res.ok then
		NotifyClient(source, {
			kind = "bank",
			code = "debited",
			title = "Charge successful",
			message = ("Debited $%s."):format(tostring(amount)),
			amount = amount,
			reference = reference,
			txId = res.txId,
			groupId = res.groupId,

			-- NEW: for BankApp notifications
			balanceBefore = res.balanceBefore,
			balanceAfter = res.balanceAfter
		})
	else
		local err = tostring(res and res.error or "unknown_error")

		local msg = "Charge failed."
		if err == "no_bank_account" then
			msg = ("No bank account found. $%s was not debited."):format(tostring(amount))
		elseif err == "sender_locked" then
			msg = "Bank account is locked. Charge not processed."
		elseif err == "not_enough_money" then
			msg = ("Not enough funds. Balance: $%s."):format(tostring(res and res.balance or "0"))
		elseif err == "db_update_failed" then
			msg = "Database update failed. Charge not processed."
		end

		NotifyClient(source, {
			kind = "bank",
			code = err,
			title = "Charge failed",
			message = msg,
			amount = amount,
			reference = reference
		})
	end
end)
