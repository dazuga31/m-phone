local Shared = require("WidgetSDK.shared")
local SDK = { widgets = {}, handlers = {} }

local function EntryEnabled(entry)
	local feature = type(entry) == "table" and tostring(entry.Feature or "") or ""
	return feature == "" or not Config or not Config.IsFeatureEnabled or Config.IsFeatureEnabled(feature)
end

function SDK.RegisterWidget(input)
	local manifest, err = Shared.NormalizeManifest(input)
	if not manifest then return false, err end
	SDK.widgets[manifest.id] = manifest
	return true, manifest.id
end

RegisterServerEvent("m-phone:widgetSdk:request", function(a, b)
	local controller, request = Shared.ResolveControllerAndPayload(a, b)
	local requestId = tostring(request.requestId or "")
	local widgetId = string.lower(tostring(request.widgetId or ""))
	local response = { requestId = requestId, widgetId = widgetId, ok = false }
	local manifest = SDK.widgets[widgetId]
	local handler = SDK.handlers[widgetId]
	if not manifest then response.error = "widget_not_registered"
	elseif not Shared.SupportsSurface(manifest, request.context) then response.error = "widget_surface_unsupported"
	else
		local ok, result = pcall(function()
			if handler then
				return handler(controller, tostring(request.action or "open"), type(request.payload) == "table" and request.payload or {}, type(request.context) == "table" and request.context or {})
			end
			if not exports or not exports[manifest.provider] then return { ok = false, error = "provider_unavailable" } end
			local providerExports = exports[manifest.provider]
			local method = providerExports[manifest.serverExport]
			if method == nil then return { ok = false, error = "provider_export_missing" } end
			return method(providerExports, manifest.id, controller, tostring(request.action or "open"), type(request.payload) == "table" and request.payload or {}, type(request.context) == "table" and request.context or {})
		end)
		if not ok then response.error = "provider_failed"; response.details = tostring(result)
		else result = type(result) == "table" and result or { ok = true, value = result }; response.ok = result.ok ~= false; response.data = result; response.error = result.error end
	end
	TriggerClientEvent(controller, "m-phone:widgetSdk:response", response)
end)

exports("m-phone", "RegisterWidget", function(manifest) return SDK.RegisterWidget(manifest) end)
for _, entry in ipairs(Config.WidgetSDK.Widgets or {}) do
	if EntryEnabled(entry) then
		local manifestOk, manifest = pcall(require, tostring(entry.Manifest or ""))
		if manifestOk then
			local registered = SDK.RegisterWidget(manifest)
			if registered and tostring(entry.Server or "") ~= "" then
				local serverOk, provider = pcall(require, entry.Server)
				if serverOk and type(provider) == "table" and type(provider.HandleRequest) == "function" then SDK.handlers[manifest.id] = provider.HandleRequest end
			end
		end
	end
end

return SDK
