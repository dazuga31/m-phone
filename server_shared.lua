-- m-phone/server_shared.lua

local Shared = {}

function Shared.NowMs()
	return math.floor(os.time() * 1000)
end

function Shared.TableToString(t, depth)
	depth = depth or 0

	if depth > 3 then
		return "<max_depth>"
	end

	if type(t) ~= "table" then
		return tostring(t)
	end

	local out = {}

	for k, v in pairs(t) do
		local key = tostring(k)

		if type(v) == "table" then
			out[#out + 1] = key .. "=" .. Shared.TableToString(v, depth + 1)
		else
			out[#out + 1] = key .. "=" .. tostring(v)
		end
	end

	return "{" .. table.concat(out, ", ") .. "}"
end

function Shared.ResolveControllerAndPayload(a, b)
	if type(a) == "userdata" or type(a) == "number" then
		return a, b
	end

	return source, a
end

return Shared
