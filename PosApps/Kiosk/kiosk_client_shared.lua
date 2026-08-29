-- m-phone/PosApps/Kiosk/kiosk_client_shared.lua

local Shared = {}

function Shared.NowMsSafe()
	if type(NowMs) == "function" then return NowMs() end
	return (os.time() * 1000) + math.random(0, 999)
end

function Shared.NextReqId(seq)
	return tostring(Shared.NowMsSafe()) .. "-" .. tostring(seq)
end

function Shared.SetTimeout(ms, fn)
	ms = math.max(1, tonumber(ms) or 1)
	if type(fn) ~= "function" then return nil end

	if Timer and type(Timer.SetTimeout) == "function" then
		local ok, handle = pcall(function()
			return Timer.SetTimeout(fn, ms)
		end)
		if ok then return handle end
	end

	if Timer and type(Timer.SetInterval) == "function" and type(Timer.ClearInterval) == "function" then
		local handle = nil
		handle = Timer.SetInterval(function()
			if handle then Timer.ClearInterval(handle) end
			handle = nil
			fn()
		end, ms)
		return handle
	end

	fn()
	return nil
end

return Shared
