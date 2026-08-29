local SpatialWebUI = {}

local REPLAY_EVENTS = {
	["setvisible"] = true,
	["opendesktop"] = true,
	["helix:data:payload"] = true,
}

local function ResolveProvider()
	if not exports then return nil, nil end
	local resourceName = tostring(
		Config and Config.Desktop and Config.Desktop.Resource or "m-desktop"
	)
	local providerOk, provider = pcall(function()
		return exports[resourceName]
	end)
	if not providerOk or not provider then return nil, resourceName end
	return provider, resourceName
end

local function CallProvider(methodName, ...)
	local provider, resourceName = ResolveProvider()
	if not provider then
		return false, "provider_unavailable:" .. tostring(resourceName or "m-desktop")
	end

	local methodOk, method = pcall(function()
		return provider[methodName]
	end)
	if not methodOk or type(method) ~= "function" then
		return false, "provider_export_missing:" .. tostring(methodName)
	end

	local ok, first, second = pcall(method, provider, ...)
	if not ok then return false, tostring(first) end
	return true, first, second
end

function SpatialWebUI.CreateRouter(screenUI, options)
	options = type(options) == "table" and options or {}
	local router = {
		Screen = screenUI,
		Spatial = nil,
		NativeSpatialActive = false,
		Active = screenUI,
		Events = {},
		Log = options.log,
		IsOpen = options.isOpen,
		OnSpatialStateChanged = options.onSpatialStateChanged,
		SpatialGeneration = 0,
	}

	local function Log(message, payload)
		if type(router.Log) == "function" then
			pcall(router.Log, message, payload)
		end
	end

	local function NotifySpatialState(active, definition)
		if type(router.OnSpatialStateChanged) == "function" then
			pcall(router.OnSpatialStateChanged, active == true, definition)
		end
	end

	local function ResetToScreen(notify)
		router.Spatial = nil
		router.NativeSpatialActive = false
		router.Active = router.Screen
		router.SpatialGeneration = router.SpatialGeneration + 1
		if router.Screen then
			pcall(function() router.Screen:SetInputMode(0) end)
			local shouldRestore = type(router.IsOpen) == "function"
				and router.IsOpen() == true
			if shouldRestore then
				pcall(function() router.Screen:SendEvent("setVisible", true) end)
				pcall(function() router.Screen:SetInputMode(1) end)
			end
		end
		if notify ~= false then NotifySpatialState(false) end
	end

	function router:RegisterEventHandler(eventName, callback)
		local name = tostring(eventName or "")
		if name == "" or type(callback) ~= "function" then return self end
		self.Events[name:lower()] = {
			name = name,
			callback = callback,
		}
		if self.Screen then self.Screen:RegisterEventHandler(name, callback) end
		if self.Spatial then self.Spatial:RegisterEventHandler(name, callback) end
		return self
	end

	function router:AttachSpatialUI(spatial, definition)
		if not spatial then return false, "invalid_spatial_ui" end
		if self.Spatial == spatial then return true end

		for _, binding in pairs(self.Events) do
			local ok, err = pcall(function()
				spatial:RegisterEventHandler(binding.name, binding.callback)
			end)
			if not ok then
				return false, "event_binding_failed:" .. tostring(binding.name) .. ":" .. tostring(err)
			end
		end

		self.Spatial = spatial
		self.NativeSpatialActive = false
		self.Active = spatial
		self.SpatialGeneration = self.SpatialGeneration + 1
		if self.Screen then
			pcall(function() self.Screen:SendEvent("setVisible", false) end)
			pcall(function() self.Screen:SetInputMode(0) end)
		end
		NotifySpatialState(true, definition)
		Log("spatial UI attached to m-phone bridge", {
			id = type(definition) == "table" and definition.id or nil,
		})
		return true
	end

	function router:DetachSpatialUI(spatial)
		if spatial and self.Spatial and spatial ~= self.Spatial then
			return false, "spatial_ui_mismatch"
		end
		if not self.Spatial then return true end
		ResetToScreen(true)
		Log("spatial UI detached from m-phone bridge")
		return true
	end

	function router:SetNativeSpatialState(active, definition)
		active = active == true
		if active then
			self.Spatial = nil
			self.NativeSpatialActive = true
			self.Active = self.Screen
			self.SpatialGeneration = self.SpatialGeneration + 1
			if self.Screen then
				pcall(function() self.Screen:SendEvent("setVisible", false) end)
				pcall(function() self.Screen:SetInputMode(0) end)
			end
			NotifySpatialState(true, definition)
			return true
		end

		if self.NativeSpatialActive then ResetToScreen(true) end
		return true
	end

	function router:SendEvent(eventName, ...)
		local active = self.Active
		if active then active:SendEvent(eventName, ...) end

		local eventKey = tostring(eventName or ""):lower()
		if self.Spatial and REPLAY_EVENTS[eventKey]
			and Timer and type(Timer.SetTimeout) == "function" then
			local spatial = self.Spatial
			local generation = self.SpatialGeneration
			local args = { ... }
			for _, delay in ipairs({ 200, 500 }) do
				Timer.SetTimeout(function()
					if self.Spatial == spatial and self.SpatialGeneration == generation then
						spatial:SendEvent(eventName, table.unpack(args))
					end
				end, delay)
			end
		end
		return self
	end

	function router:SetInputMode(inputMode)
		local mode = tonumber(inputMode) or 0
		if self.Spatial then
			pcall(function() self.Spatial:SetInputMode(0) end)
			if mode > 0 then CallProvider("RefreshSpatialDesktopCamera") end
		elseif self.NativeSpatialActive then
			if mode > 0 then CallProvider("RefreshSpatialDesktopCamera") end
		elseif self.Screen then
			self.Screen:SetInputMode(mode)
		end

		if mode == 0 and self:IsSpatialWidget() then
			self:DeactivateSpatial()
		end
		return self
	end

	function router:BringToFront()
		if self.Active then self.Active:BringToFront() end
		return self
	end

	function router:SetStackOrder(order)
		if self.Active then self.Active:SetStackOrder(order) end
		return self
	end

	function router:IsReady()
		return self.Active ~= nil and self.Active:IsReady()
	end

	function router:IsSpatialWidget()
		return self.Spatial ~= nil or self.NativeSpatialActive == true
	end

	function router:ActivateSpatial(definition)
		local ok, result, reason = CallProvider("ActivateSpatialDesktop", definition)
		if not ok then return false, result end
		return result ~= false, reason
	end

	function router:ActivateNativeSpatial(definition)
		local ok, result, reason = CallProvider("ActivateNativeSpatialDesktop", definition)
		if not ok then return false, result end
		return result ~= false, reason
	end

	function router:DeactivateSpatial()
		local ok, result, reason = CallProvider("DeactivateSpatialDesktop")
		if not ok or result == false then
			ResetToScreen(true)
			return false, ok and reason or result
		end
		return true
	end

	function router:Destroy()
		if self:IsSpatialWidget() then self:DeactivateSpatial() end
		if self.Screen then
			pcall(function() self.Screen:Destroy() end)
			self.Screen = nil
			self.Active = nil
		end
	end

	return router
end

return SpatialWebUI
