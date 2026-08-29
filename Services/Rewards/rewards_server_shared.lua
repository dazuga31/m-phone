-- scripts/m-phone/Extras/rewards_server_shared.lua

local Shared = {}

function Shared.NowMsSafe()
	if type(NowMs) == "function" then
		return NowMs()
	end
	return os.time() * 1000
end

function Shared.NotifyClient(src, payload)
	TriggerClientEvent(src, "m-phone:bank:notify", payload)
end

function Shared.LogInfo(msg)
	print("[m-phone][server][Rewards][info] " .. tostring(msg))
end

function Shared.LogWarn(msg)
	print("[m-phone][server][Rewards][warn] " .. tostring(msg))
end

function Shared.LogErr(msg)
	print("[m-phone][server][Rewards][error] " .. tostring(msg))
end

function Shared.NormalizeAmount(v)
	local n = tonumber(v) or 0
	n = math.floor(n + 0.0)
	return n
end

function Shared.NormalizeText(v, fallback)
	local s = tostring(v or "")
	if s == "" then s = tostring(fallback or "") end
	return s
end

function Shared.FormatMoneyFromCents(cents)
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

return Shared
