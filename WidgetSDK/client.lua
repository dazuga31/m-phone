local Shared = require("WidgetSDK.shared")

local SDK = { widgets = {}, handlers = {}, ui = nil }

local function Enabled() return Config and Config.WidgetSDK and Config.WidgetSDK.Enabled ~= false end
local function EntryEnabled(entry)
	local feature = type(entry) == "table" and tostring(entry.Feature or "") or ""
	return feature == "" or not Config or not Config.IsFeatureEnabled or Config.IsFeatureEnabled(feature)
end
local function PublicWidgets()
	local result = {}
	for _, manifest in pairs(SDK.widgets) do result[#result + 1] = Shared.CopyPublicManifest(manifest) end
	table.sort(result, function(a, b) return a.order == b.order and a.id < b.id or a.order < b.order end)
	return result
end
local function Payload() return { sdkVersion = tonumber(Config.WidgetSDK.Version) or 1, widgets = PublicWidgets() } end
local function PushRegistry() if SDK.ui then SDK.ui:SendEvent("widgetSdk:registry", Payload()) end end
local function Respond(payload) if SDK.ui then SDK.ui:SendEvent("widgetSdk:response", payload) end end

function SDK.RegisterWidget(input)
	if not Enabled() then return false, "widget_sdk_disabled" end
	local manifest, err = Shared.NormalizeManifest(input)
	if not manifest then return false, err end
	if manifest.sdkVersion > (tonumber(Config.WidgetSDK.Version) or 1) then return false, "sdk_version_unsupported" end
	SDK.widgets[manifest.id] = manifest
	PushRegistry()
	return true, manifest.id
end

function SDK.RegisterClientHandler(widgetId, handler)
	widgetId = string.lower(tostring(widgetId or ""))
	if widgetId == "" or type(handler) ~= "function" then return false, "handler_invalid" end
	SDK.handlers[widgetId] = handler
	return true, widgetId
end

function SDK.BindUI(ui)
	SDK.ui = ui
	if not ui then return false end
	ui:RegisterEventHandler("widgetSdk:getRegistry", function(_, cb) local value = Payload(); PushRegistry(); if cb then cb(value) end end)
	ui:RegisterEventHandler("widgetSdk:request", function(request, cb)
		request = type(request) == "table" and request or {}
		local id = string.lower(tostring(request.widgetId or ""))
		local requestId = tostring(request.requestId or "")
		local manifest = SDK.widgets[id]
		if requestId == "" or not manifest then if cb then cb({ ok = false, error = "widget_request_invalid" }) end return end
		if not Shared.SupportsSurface(manifest, request.context) then
			local response = { requestId = requestId, widgetId = id, ok = false, error = "widget_surface_unsupported" }
			Respond(response)
			if cb then cb(response) end
			return
		end
		local handler = SDK.handlers[id]
		if handler then
			local completed = false
			local function done(result)
				if completed then return end
				completed = true
				result = type(result) == "table" and result or { ok = true, value = result }
				Respond({ requestId = requestId, widgetId = id, ok = result.ok ~= false, data = result, error = result.error })
			end
			local ok, result = pcall(handler, tostring(request.action or "open"), type(request.payload) == "table" and request.payload or {}, type(request.context) == "table" and request.context or {}, done)
			if not ok then
				done({ ok = false, error = "client_handler_failed", details = tostring(result) })
			elseif type(result) == "table" and result.forwardToServer == true then
				completed = true
				TriggerServerEvent("m-phone:widgetSdk:request", request)
			elseif result ~= nil then
				done(result)
			end
		else
			TriggerServerEvent("m-phone:widgetSdk:request", request)
		end
		if cb then cb({ ok = true, accepted = true, requestId = requestId }) end
	end)
	PushRegistry()
	return true
end

RegisterClientEvent("m-phone:widgetSdk:response", function(payload) Respond(type(payload) == "table" and payload or {}) end)
exports("m-phone", "RegisterWidget", function(manifest) return SDK.RegisterWidget(manifest) end)
exports("m-phone", "RegisterWidgetClientHandler", function(widgetId, handler) return SDK.RegisterClientHandler(widgetId, handler) end)
exports("m-phone", "GetRegisteredWidgets", PublicWidgets)

for _, entry in ipairs(Config.WidgetSDK.Widgets or {}) do
	if EntryEnabled(entry) then
		local manifestOk, manifest = pcall(require, tostring(entry.Manifest or ""))
		if manifestOk then
			local registered, reason = SDK.RegisterWidget(manifest)
			if registered and tostring(entry.Client or "") ~= "" then
				local clientOk, provider = pcall(require, entry.Client)
				if clientOk and type(provider) == "table" then
					if type(provider.HandleRequest) == "function" then SDK.handlers[manifest.id] = provider.HandleRequest
					elseif type(provider.Handlers) == "table" and type(provider.Handlers[manifest.id]) == "function" then SDK.handlers[manifest.id] = provider.Handlers[manifest.id] end
				end
			end
			print(("[m-phone][WidgetSDK][client] %s: %s"):format(tostring(entry.Manifest), registered and "registered" or tostring(reason)))
		else print(("[m-phone][WidgetSDK][client] manifest failed %s: %s"):format(tostring(entry.Manifest), tostring(manifest))) end
	else print(("[m-phone][WidgetSDK][client] feature disabled, skipped %s"):format(tostring(entry.Manifest))) end
end

return SDK
