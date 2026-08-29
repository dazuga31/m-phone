-- scripts/m-phone/Extras/rewards_client.lua

local Core = _G.MPhoneClient
if not Core then
	print("[m-phone][Rewards][error] _G.MPhoneClient not found")
	return
end

local function FormatMoney(n)
	if type(n) ~= "number" then return nil end
	-- simple safe formatter (no commas)
	return tostring(math.floor(n + 0.5))
end

local function SendPersistedChat(chatId, chatName, text, priority, ttlMs, appId, sender)
	TriggerServerEvent("m-phone:chat:sendSystem", {
		chatId = tostring(chatId or ""),
		chatName = tostring(chatName or "Message"),
		text = tostring(text or ""),
		priority = priority or "normal",
		ttlMs = tonumber(ttlMs) or 4000,
		appId = tostring(appId or "chat"),
		sender = tostring(sender or "system"),
		createdAtMs = math.floor(os.time() * 1000),
	})
end


-- Test trigger (dev bridge)
RegisterClientEvent("m-phone:rewards:testPayout", function()
	print("[m-phone][debug] testPayout -> server")

	TriggerServerEvent("m-phone:rewards:testPayout", {
		amount = 2500,
		reference = "Delivery reward (test)"
	})
end)

-- Optional: keep this for future HUD notifications (not used by current server module)
RegisterClientEvent("m-phone:rewards:notify", function(payload)
	if type(payload) ~= "table" then return end

	local text = tostring(payload.text or "")
	local delay = tonumber(payload.delay) or 1.5
	local posKey = tostring(payload.position or "TopRight")

	if type(Notification) == "function" and NotificationPosition then
		local pos = NotificationPosition[posKey] or NotificationPosition.TopRight
		Notification(text, delay, pos)
	else
		print(("[m-phone][Rewards][warn] Notification API missing. text=%s"):format(text))
	end
end)

-- Test trigger (dev bridge) - DEBIT
RegisterClientEvent("m-phone:bank:testDebit", function()
	print("[m-phone][debug] testDebit -> server")

	TriggerServerEvent("m-phone:bank:testDebit", {
		amount = 150,
		reference = "Kiosk purchase (test debit)",

		-- optional: simulate condition check
		requireFlag = true,
		flag = true,
	})
end)

-- =========================
-- Bank notify -> Chat + notify:phone (badge)
-- =========================

local function FormatMoneyFromCents(cents)
	cents = tonumber(cents) or 0
	local sign = ""
	if cents < 0 then
		sign = "-"
		cents = math.abs(cents)
	end

	local dollars = math.floor(cents / 100)
	local centsPart = cents % 100

	return string.format("%s%d.%02d", sign, dollars, centsPart)
end

-- =========================
-- Bank notify -> Chat + notify:phone (badge)
-- =========================

local function FormatMoneyFromCents(cents)
	cents = tonumber(cents) or 0
	local sign = ""
	if cents < 0 then
		sign = "-"
		cents = math.abs(cents)
	end

	local dollars = math.floor(cents / 100)
	local centsPart = cents % 100

	return string.format("%s%d.%02d", sign, dollars, centsPart)
end

RegisterClientEvent("m-phone:bank:notify", function(payload)
	if type(payload) ~= "table" then return end

	print(("[m-phone][bank][notify] code=%s title=%s message=%s amount=%s ref=%s txId=%s"):format(
		tostring(payload.code or ""),
		tostring(payload.title or ""),
		tostring(payload.message or ""),
		tostring(payload.amount or ""),
		tostring(payload.reference or ""),
		tostring(payload.txId or "")
	))

	local ref = tostring(payload.reference or "")
	local code = string.lower(tostring(payload.code or ""))

	if code == "debited" then
		local amountText = tostring(payload.amountText or FormatMoneyFromCents(payload.amount) or "?")
		local balanceText = tostring(payload.balanceAfterText or FormatMoneyFromCents(payload.balanceAfter) or "?")
		local message = ("Charged $%s. Available balance: $%s. %s"):format(
			amountText,
			balanceText,
			ref ~= "" and ref or "Payment"
		)
		local title = tostring(payload.title or "Bank account")

		if type(TriggerLocalClientEvent) == "function" then
			TriggerLocalClientEvent("HEvent:ShowNotification", "info", title, message, 4500)
		elseif type(Notification) == "function" and NotificationType then
			Notification(message, NotificationType.Info, 4.5)
		end
	end

	-- Chat notify for TEST DEBIT (kiosk purchase)
	do
		local isTestDebit = ref:find("test debit", 1, true) ~= nil
			or ref:find("kiosk purchase", 1, true) ~= nil

		if isTestDebit then
			local amount = tostring(payload.amountText or FormatMoneyFromCents(payload.amount) or "")
			local title = "Kiosk"

			local ok = (code == "ok")
				or (code:find("success", 1, true) ~= nil)
				or (code:find("debit_ok", 1, true) ~= nil)
				or (code:find("paid", 1, true) ~= nil)
				or (code == "debited")

			local text
			local prio = "high"

			if ok then
				text = ("Payment successful. You were charged %s$. Ref: %s"):format(
					amount ~= "" and amount or "?",
					ref ~= "" and ref or "-"
				)
			else
				local msg = tostring(payload.message or payload.title or "Payment failed")
				text = ("Payment failed. %s Ref: %s"):format(msg, ref ~= "" and ref or "-")
			end

			-- appId="chat" -> badge on Chat app (phone)
			SendPersistedChat("system:kiosk", title, text, prio, 4000, "chat", "system")
		end
	end

	-- BankApp: balance change notification (credit/debit)
	do
		local amountNumCents = tonumber(payload.amount) or 0

		local isCredit = (code == "credited")
		local isDebit = (code == "debited")

		if (isCredit or isDebit) and amountNumCents > 0 then
			local sign = isCredit and "+" or "-"
			local chatId = "system:bank"
			local chatName = "Bank"
			local prio = "normal"
			local ttl = 4200

			-- prefer preformatted money strings from server (if provided)
			local amountStr = tostring(payload.amountText or FormatMoneyFromCents(amountNumCents) or "?")

			local afterStr = nil
			if payload.balanceAfterText ~= nil then
				afterStr = tostring(payload.balanceAfterText)
			else
				local balAfterCents = tonumber(payload.balanceAfter)
				if balAfterCents ~= nil then
					afterStr = FormatMoneyFromCents(balAfterCents)
				end
			end

			local beforeStr = nil
			if payload.balanceBeforeText ~= nil then
				beforeStr = tostring(payload.balanceBeforeText)
			else
				local balBeforeCents = tonumber(payload.balanceBefore)
				if balBeforeCents ~= nil then
					beforeStr = FormatMoneyFromCents(balBeforeCents)
				end
			end

			local text
			if afterStr ~= nil then
				if beforeStr ~= nil then
					text = ("Balance updated: %s$%s. $%s -> $%s. Ref: %s"):format(
						sign,
						amountStr,
						beforeStr,
						afterStr,
						ref ~= "" and ref or "-"
					)
				else
					text = ("Balance updated: %s$%s. New balance: $%s. Ref: %s"):format(
						sign,
						amountStr,
						afterStr,
						ref ~= "" and ref or "-"
					)
				end
			else
				text = ("Balance updated: %s$%s. Ref: %s"):format(
					sign,
					amountStr,
					ref ~= "" and ref or "-"
				)
			end

			-- appId="chat" -> badge on Chat app (phone)
			SendPersistedChat(chatId, chatName, text, prio, ttl, "chat", "system")
		end
	end
end)


print("[m-phone][client] Rewards client module LOADED")
