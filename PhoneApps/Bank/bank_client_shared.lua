-- m-phone/PhoneApps/Bank/bank_client_shared.lua

local Shared = {}

function Shared.NextReqId(seq)
	return tostring(os.time()) .. "-" .. tostring(seq)
end

function Shared.NowMs()
	return math.floor(os.time() * 1000)
end

function Shared.SetTimeout(pending, core, requestId, cb, ms)
	ms = tonumber(ms) or 3000

	if Threading and Threading.SetTimeout then
		Threading.SetTimeout(ms, function()
			if pending[requestId] then
				pending[requestId] = nil
				if cb then
					cb({
						requestId = tostring(requestId),
						ok = false,
						error = "timeout_server",
						profile = nil,
						account = nil,
						meta = { timestamp = Shared.NowMs() }
					})
				end
			end
		end)
		return
	end

	-- WebUI owns the fallback timeout when HELIX has no client timeout API.
end

return Shared
