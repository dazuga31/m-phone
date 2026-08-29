local Bridge = {}

local function Core()
	if not exports then return nil end
	local ok, value = pcall(function() return exports["qb-core"] end)
	return ok and value or nil
end

local function AccountId(controller)
	if controller == nil then return "" end
	local stateOk, playerState = pcall(function() return controller:GetLyraPlayerState() end)
	if not stateOk or playerState == nil then return "" end
	local idOk, value = pcall(function() return playerState:GetHelixUserId() end)
	if not idOk or value == nil then return "" end
	local id = tostring(value):match("^%s*(.-)%s*$") or ""
	if id == "" then return "" end
	return string.sub(string.lower(id), 1, 6) == "helix:" and id or ("helix:" .. id)
end

function Bridge.GetPlayer(controller)
	local qb = Core()
	if not qb then return nil, "qb_core_unavailable" end
	local ok, player = pcall(function() return qb:GetPlayer(controller) end)
	if not ok or type(player) ~= "table" or type(player.PlayerData) ~= "table" then
		return nil, "player_unavailable"
	end
	local data = player.PlayerData
	local charinfo = type(data.charinfo) == "table" and data.charinfo or {}
	local firstName = tostring(charinfo.firstname or data.firstname or "")
	local lastName = tostring(charinfo.lastname or data.lastname or "")
	local displayName = (firstName .. " " .. lastName):match("^%s*(.-)%s*$")
	return {
		controller = controller,
		player = player,
		accountId = AccountId(controller),
		citizenId = tostring(data.citizenid or ""),
		displayName = displayName ~= "" and displayName or tostring(data.name or "Player"),
	}
end

function Bridge.AddCash(snapshot, amount, reason)
	if type(snapshot) ~= "table" or type(snapshot.player) ~= "table" then return false, "player_unavailable" end
	local functions = snapshot.player.Functions
	if type(functions) ~= "table" or type(functions.AddMoney) ~= "function" then return false, "money_api_unavailable" end
	local ok, result = pcall(function() return functions.AddMoney("cash", tonumber(amount) or 0, tostring(reason or "creatorlink_reward")) end)
	if not ok then return false, tostring(result) end
	return result ~= false, result == false and "money_add_failed" or nil
end

function Bridge.RemoveCash(snapshot, amount, reason)
	if type(snapshot) ~= "table" or type(snapshot.player) ~= "table" then return false, "player_unavailable" end
	local functions = snapshot.player.Functions
	if type(functions) ~= "table" or type(functions.RemoveMoney) ~= "function" then return false, "money_api_unavailable" end
	local ok, result = pcall(function()
		return functions.RemoveMoney("cash", tonumber(amount) or 0, tostring(reason or "creatorlink_reward_rollback"))
	end)
	if not ok then return false, tostring(result) end
	return result ~= false, result == false and "money_remove_failed" or nil
end

function Bridge.Database(action, sql, params)
	local qb = Core()
	if not qb then return nil, "qb_core_unavailable" end
	local ok, result = pcall(function() return qb:DatabaseAction(action, sql, params or {}) end)
	if not ok then return nil, tostring(result) end
	return result
end

return Bridge

