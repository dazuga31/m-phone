local CreatorLink = {
	ui = nil,
	notifier = nil,
	pollTimer = nil,
	backgroundRequests = {},
	lastApplicationState = nil,
	lastExpiryWarning = nil,
}
local requestSequence = 0
local POLL_INTERVAL_MS = 45000

local function NextRequestId()
	requestSequence = requestSequence + 1
	return string.format("creatorlink_%d_%d", os.time(), requestSequence)
end

local function Notify(payload)
	if type(CreatorLink.notifier) ~= "function" then return false end
	local ok, result = pcall(CreatorLink.notifier, payload)
	return ok and result ~= false
end

local function ApplicationStatusText(status)
	local labels = {
		reviewing = "Your creator partner application is now in review.",
		approved = "Your creator partner application was approved.",
		rejected = "Your creator partner application was not approved.",
		cancelled = "Your creator partner application was cancelled.",
	}
	return labels[tostring(status or "")]
end

local function HandleBackgroundState(payload)
	if type(payload) ~= "table" or payload.ok ~= true then return end
	local application = type(payload.partnerApplication) == "table" and payload.partnerApplication or nil
	if application and tostring(application.id or "") ~= "" and tostring(application.status or "") ~= "" then
		local current = tostring(application.id) .. ":" .. tostring(application.status)
		if CreatorLink.lastApplicationState and CreatorLink.lastApplicationState ~= current then
			local text = ApplicationStatusText(application.status)
			if text then
				Notify({
					kind = "system",
					appId = "creatorlink",
					title = "CreatorLink",
					text = text,
					ttlMs = 5200,
					priority = application.status == "approved" and "high" or "normal",
				})
			end
		end
		CreatorLink.lastApplicationState = current
	end

	local activeLink = type(payload.activeLink) == "table" and payload.activeLink or nil
	local expiresAt = activeLink and tonumber(activeLink.expiresAt) or 0
	local remaining = expiresAt > 0 and math.max(0, math.ceil((expiresAt - os.time()) / 86400)) or 0
	if activeLink and tostring(activeLink.code or "") ~= "" and remaining > 0 and remaining <= 3 then
		local warningKey = tostring(activeLink.code) .. ":" .. tostring(expiresAt)
		if CreatorLink.lastExpiryWarning ~= warningKey then
			CreatorLink.lastExpiryWarning = warningKey
			Notify({
				kind = "system",
				appId = "creatorlink",
				title = "CreatorLink",
				text = string.format("Your %s support cycle ends in %d day%s.", tostring(activeLink.partnerName or activeLink.code), remaining, remaining == 1 and "" or "s"),
				ttlMs = 4800,
				priority = "normal",
			})
		end
	end
end

local function PollState()
	local requestId = NextRequestId()
	CreatorLink.backgroundRequests[requestId] = true
	TriggerServerEvent("m-phone:creatorlink:request", {
		requestId = requestId,
		action = "getState",
		payload = {},
	})
end

local function StartPolling()
	if CreatorLink.pollTimer ~= nil or not Timer or type(Timer.SetInterval) ~= "function" then return end
	if type(Timer.SetTimeout) == "function" then
		Timer.SetTimeout(PollState, 3000)
	else
		PollState()
	end
	CreatorLink.pollTimer = Timer.SetInterval(PollState, POLL_INTERVAL_MS)
end

function CreatorLink.SetNotifier(notifier)
	CreatorLink.notifier = type(notifier) == "function" and notifier or nil
end

function CreatorLink.BindUI(ui)
	CreatorLink.ui = ui
	if not ui then return false end
	ui:RegisterEventHandler("creatorlink:request", function(input, cb)
		input = type(input) == "table" and input or {}
		local requestId = NextRequestId()
		TriggerServerEvent("m-phone:creatorlink:request", {
			requestId = requestId,
			action = tostring(input.action or "getState"),
			payload = type(input.payload) == "table" and input.payload or {},
		})
		if cb then cb({ ok = true, accepted = true, requestId = requestId }) end
	end)
	StartPolling()
	return true
end

RegisterClientEvent("m-phone:creatorlink:response", function(payload)
	payload = type(payload) == "table" and payload or {}
	local requestId = tostring(payload.requestId or "")
	if CreatorLink.backgroundRequests[requestId] then
		CreatorLink.backgroundRequests[requestId] = nil
		HandleBackgroundState(payload)
	end
	if CreatorLink.ui then CreatorLink.ui:SendEvent("creatorlink:response", type(payload) == "table" and payload or {}) end
end)

return CreatorLink
