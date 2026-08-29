local VoiceAdapter = {}
VoiceAdapter.__index = VoiceAdapter

local function NormalizeProvider(value)
	return tostring(value or "none"):lower()
end

function VoiceAdapter.New(options)
	options = type(options) == "table" and options or {}
	local config = type(options.Config) == "table" and options.Config or {}
	local firstChannel = math.floor(tonumber(config.ChannelStart) or 70000)
	local lastChannel = math.floor(tonumber(config.ChannelEnd) or 79999)
	if lastChannel < firstChannel then lastChannel = firstChannel end

	return setmetatable({
		enabled = config.Enabled ~= false,
		provider = NormalizeProvider(config.Provider or "helix"),
		firstChannel = firstChannel,
		lastChannel = lastChannel,
		nextChannel = firstChannel,
		channelsByCall = {},
		callsByChannel = {},
		logInfo = options.LogInfo or function() end,
		logWarn = options.LogWarn or function() end,
	}, VoiceAdapter)
end

function VoiceAdapter:IsEnabled()
	return self.enabled and self.provider == "helix"
end

function VoiceAdapter:ResolvePlayer(controller)
	if not controller then return nil, "controller_unavailable" end
	local okMethod, getByIndex = pcall(function() return HPlayer and HPlayer.GetByIndex end)
	if not okMethod or getByIndex == nil then
		return nil, "helix_voice_api_unavailable"
	end

	local ok, player = pcall(getByIndex, HPlayer, controller)
	if not ok then return nil, tostring(player) end
	if not player then return nil, "helix_player_unavailable" end
	return player
end

function VoiceAdapter:AllocateChannel(callId)
	local existing = self.channelsByCall[callId]
	if existing then return existing end

	local capacity = self.lastChannel - self.firstChannel + 1
	for _ = 1, capacity do
		local channelId = self.nextChannel
		self.nextChannel = channelId >= self.lastChannel and self.firstChannel or channelId + 1
		if not self.callsByChannel[channelId] then
			self.channelsByCall[callId] = channelId
			self.callsByChannel[channelId] = callId
			return channelId
		end
	end
	return nil, "voice_channel_pool_exhausted"
end

function VoiceAdapter:ReleaseChannel(callId, channelId)
	channelId = channelId or self.channelsByCall[callId]
	self.channelsByCall[callId] = nil
	if channelId and self.callsByChannel[channelId] == callId then
		self.callsByChannel[channelId] = nil
	end
end

function VoiceAdapter:JoinPlayer(controller, channelId)
	local player, resolveError = self:ResolvePlayer(controller)
	if not player then return false, resolveError end
	local okMethod, method = pcall(function() return player.JoinVoiceChannel end)
	if not okMethod or method == nil then return false, "join_voice_channel_unavailable" end

	local ok, result = pcall(method, player, channelId)
	if not ok then return false, tostring(result) end
	if result == false then return false, "join_voice_channel_rejected" end
	return true
end

function VoiceAdapter:LeavePlayer(controller, channelId)
	local player, resolveError = self:ResolvePlayer(controller)
	if not player then return false, resolveError end
	local okMethod, method = pcall(function() return player.LeaveVoiceChannel end)
	if not okMethod or method == nil then return false, "leave_voice_channel_unavailable" end

	local ok, result = pcall(method, player, channelId)
	if not ok then return false, tostring(result) end
	if result == false then return false, "leave_voice_channel_rejected" end
	return true
end

function VoiceAdapter:SetPlayerMuted(controller, channelId, muted)
	local player, resolveError = self:ResolvePlayer(controller)
	if not player then return false, resolveError end
	local methodName = muted == true and "MuteInVoiceChannel" or "UnmuteInVoiceChannel"
	local okMethod, method = pcall(function() return player[methodName] end)
	if not okMethod or method == nil then
		return false, muted == true and "mute_voice_channel_unavailable" or "unmute_voice_channel_unavailable"
	end

	local ok, result = pcall(method, player, channelId)
	if not ok then return false, tostring(result) end
	if result == false then return false, "voice_mute_rejected" end
	return true
end

function VoiceAdapter:SetMuted(call, controller, muted)
	if type(call) ~= "table" or call.voiceConnected ~= true or not call.voiceChannelId then
		return false, "voice_not_connected"
	end
	return self:SetPlayerMuted(controller, call.voiceChannelId, muted == true)
end

function VoiceAdapter:Connect(call, callerController, recipientController)
	if not self:IsEnabled() then return false, "voice_provider_disabled" end
	if type(call) ~= "table" or tostring(call.id or "") == "" then return false, "invalid_call" end

	local channelId, allocationError = self:AllocateChannel(call.id)
	if not channelId then return false, allocationError end

	local callerJoined, callerError = self:JoinPlayer(callerController, channelId)
	if not callerJoined then
		self:ReleaseChannel(call.id, channelId)
		return false, callerError
	end

	local recipientJoined, recipientError = self:JoinPlayer(recipientController, channelId)
	if not recipientJoined then
		self:LeavePlayer(callerController, channelId)
		self:ReleaseChannel(call.id, channelId)
		return false, recipientError
	end

	call.voiceChannelId = channelId
	call.voiceConnected = true
	self.logInfo("call voice connected", { callId = call.id, channelId = channelId })
	return true, nil, channelId
end

function VoiceAdapter:Disconnect(call, callerController, recipientController)
	if type(call) ~= "table" then return false end
	local callId = tostring(call.id or "")
	local channelId = call.voiceChannelId or self.channelsByCall[callId]
	if not channelId then return true end

	if callerController then
		local ok, err = self:LeavePlayer(callerController, channelId)
		if not ok then self.logWarn("caller voice cleanup failed", { callId = callId, channelId = channelId, error = err }) end
	end
	if recipientController then
		local ok, err = self:LeavePlayer(recipientController, channelId)
		if not ok then self.logWarn("recipient voice cleanup failed", { callId = callId, channelId = channelId, error = err }) end
	end

	call.voiceConnected = false
	call.voiceChannelId = nil
	self:ReleaseChannel(callId, channelId)
	self.logInfo("call voice disconnected", { callId = callId, channelId = channelId })
	return true
end

return VoiceAdapter
