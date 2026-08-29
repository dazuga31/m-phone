-- m-phone\PhoneApps\Bank\bank_server_shared.lua

local Shared = {}

function Shared.NowMs()
	return math.floor(os.time() * 1000)
end

function Shared.ResolveSourceAndPayload(a, b)
	if type(a) == "userdata" or type(a) == "number" then
		return a, b
	end

	return source, a
end

function Shared.MaskCardNumber(cardNumber)
	cardNumber = tostring(cardNumber or "")
	local last4 = string.sub(cardNumber, -4)
	local masked = "**** **** **** " .. last4
	return masked, last4
end

function Shared.StartsWith4ByPlan(planId)
	if planId == "bronze" then return "0000" end
	if planId == "silver" then return "3333" end
	return "7777"
end

function Shared.GenCardNumber(prefix4)
	local s = tostring(prefix4 or "7777")
	while #s < 16 do
		s = s .. tostring(math.random(0, 9))
	end
	return s
end

function Shared.GetPlayerName(source)
	if source and source.GetPlayerName then
		local ok, name = pcall(function() return source:GetPlayerName() end)
		if ok and name and tostring(name) ~= "" then
			return tostring(name)
		end
	end
	return "Unknown Player"
end

function Shared.NormalizeTransferInput(data)
	data = type(data) == "table" and data or {}

	return {
		requestId = tostring(data.requestId or ""),
		recipientAccount = tostring(data.recipientAccount or ""),
		recipientName = tostring(data.recipientName or ""),
		amount = math.floor((tonumber(data.amount) or 0) + 0.0),
		reference = tostring(data.reference or ""),
	}
end

return Shared
