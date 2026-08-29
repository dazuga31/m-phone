local Adapter = {}

local function CoreName()
	local configured = Config and Config.Use and Config.Use.Core or "qb"
	configured = tostring(configured or "qb"):lower()
	if configured == "qb-core" or configured == "qbcore" then return "qb" end
	return configured
end

local function GetQBExport()
	if not exports then return nil end
	local ok, value = pcall(function()
		return exports["qb-core"]
	end)
	return ok and value or nil
end

local function GetQBPlayer(controller)
	local qb = GetQBExport()
	if not qb or not controller then return nil end
	local ok, player = pcall(function()
		return qb:GetPlayer(controller)
	end)
	return ok and type(player) == "table" and player or nil
end

local function CallQBPlayer(controller, methodName, ...)
	local qb = GetQBExport()
	if not qb or not controller then return false, "qb_core_unavailable" end
	local args = { n = select("#", ...), ... }
	local ok, result = pcall(function()
		return qb:Player(controller, tostring(methodName or ""), table.unpack(args, 1, args.n))
	end)
	if not ok then return false, tostring(result) end
	return result ~= false, result
end

local function CallPlayerFunction(snapshot, methodName, ...)
	if type(snapshot) ~= "table" or type(snapshot.player) ~= "table" then
		return false, "player_unavailable"
	end
	local functions = snapshot.player.Functions
	if functions ~= nil then
		local okMethod, method = pcall(function() return functions[tostring(methodName or "")] end)
		if okMethod and method ~= nil then
			local ok, result = pcall(method, ...)
			if ok and result ~= false then return true, result end
		end
	end
	return CallQBPlayer(snapshot.controller, methodName, ...)
end

local function PlayerSnapshot(player, controller)
	if type(player) ~= "table" or type(player.PlayerData) ~= "table" then return nil end
	local data = player.PlayerData
	local charinfo = type(data.charinfo) == "table" and data.charinfo or {}
	local metadata = type(data.metadata) == "table" and data.metadata or {}
	local firstName = tostring(charinfo.firstname or data.firstname or "")
	local lastName = tostring(charinfo.lastname or data.lastname or "")
	local fullName = (firstName .. " " .. lastName):match("^%s*(.-)%s*$")
	return {
		player = player,
		controller = controller or data.source,
		citizenId = tostring(data.citizenid or ""),
		name = fullName ~= "" and fullName or tostring(data.name or "Unknown"),
		metadata = metadata,
		charinfo = charinfo,
	}
end

function Adapter.GetPlayer(controller)
	local core = CoreName()
	if core == "qb" then
		return PlayerSnapshot(GetQBPlayer(controller), controller)
	end
	if core == "m" then
		-- Future m-core implementation belongs here.
		return nil, "m_core_not_implemented"
	end
	return nil, "unsupported_core"
end

function Adapter.GetPlayerByCitizenId(citizenId)
	local core = CoreName()
	if core == "qb" then
		local qb = GetQBExport()
		if not qb then return nil, "qb_core_unavailable" end
		local ok, player = pcall(function()
			return qb:GetPlayerByCitizenId(tostring(citizenId or ""))
		end)
		return ok and PlayerSnapshot(player) or nil
	end
	if core == "m" then
		-- Future m-core online player lookup belongs here.
		return nil, "m_core_not_implemented"
	end
	return nil, "unsupported_core"
end

function Adapter.GetPhoneNumber(snapshot)
	if type(snapshot) ~= "table" then return "" end
	local key = tostring(Config and Config.Communications and Config.Communications.PhoneNumberMetadataKey or "phoneNumber")
	local metadata = type(snapshot.metadata) == "table" and snapshot.metadata or {}
	local number = tostring(metadata[key] or "")
	if number ~= "" then return number end
	local charinfo = type(snapshot.charinfo) == "table" and snapshot.charinfo or {}
	return tostring(charinfo.phone or "")
end

function Adapter.SetPhoneNumber(snapshot, phoneNumber)
	if type(snapshot) ~= "table" or type(snapshot.player) ~= "table" then
		return false, "player_unavailable"
	end
	local core = CoreName()
	if core == "qb" then
		local key = tostring(Config and Config.Communications and Config.Communications.PhoneNumberMetadataKey or "phoneNumber")
		local ok, result = CallPlayerFunction(snapshot, "SetMetaData", key, tostring(phoneNumber))
		if not ok then return false, tostring(result or "metadata_api_unavailable") end
		snapshot.metadata = snapshot.metadata or {}
		snapshot.metadata[key] = tostring(phoneNumber)
		CallPlayerFunction(snapshot, "Save")
		return true
	end
	if core == "m" then
		-- Future m-core metadata write belongs here.
		return false, "m_core_not_implemented"
	end
	return false, "unsupported_core"
end

function Adapter.Name()
	return CoreName()
end

return Adapter
