local Shared = require("AppSDK.shared")

local SDK = {
	apps = {},
	builtinHandlers = {},
}

local function Enabled()
	return Config and Config.SDK and Config.SDK.Enabled ~= false
end

local function EntryEnabled(entry)
	local feature = type(entry) == "table" and tostring(entry.Feature or "") or ""
	return feature == "" or not Config or not Config.IsFeatureEnabled or Config.IsFeatureEnabled(feature)
end

function SDK.RegisterApp(input)
	if not Enabled() then return false, "sdk_disabled" end
	local manifest, err = Shared.NormalizeManifest(input)
	if not manifest then return false, err end
	local supportedVersion = tonumber(Config and Config.SDK and Config.SDK.Version) or 1
	if manifest.sdkVersion > supportedVersion then return false, "sdk_version_unsupported" end
	SDK.apps[manifest.id] = manifest
	return true, manifest.id
end

function SDK.RegisterBuiltinHandler(appId, handler)
	appId = string.lower(tostring(appId or ""))
	if appId == "" or type(handler) ~= "function" then return false end
	SDK.builtinHandlers[appId] = handler
	return true
end

local function DispatchProvider(manifest, controller, action, payload, context)
	if manifest.provider == "m-phone" then
		local handler = SDK.builtinHandlers[manifest.id]
		if not handler then return nil, "provider_handler_missing" end
		return handler(controller, action, payload, context)
	end

	if not exports or not exports[manifest.provider] then
		return nil, "provider_unavailable"
	end

	local providerExports = exports[manifest.provider]
	local method = providerExports[manifest.serverExport]
	if method == nil then return nil, "provider_export_missing" end
	return method(providerExports, manifest.id, controller, action, payload, context)
end

RegisterServerEvent("m-phone:sdk:request", function(a, b)
	local controller, request = Shared.ResolveControllerAndPayload(a, b)
	local requestId = tostring(request.requestId or "")
	local appId = string.lower(tostring(request.appId or ""))
	local manifest = SDK.apps[appId]

	local response = {
		requestId = requestId,
		appId = appId,
		ok = false,
	}

	if requestId == "" or not manifest then
		response.error = not manifest and "app_not_registered" or "request_id_missing"
		TriggerClientEvent(controller, "m-phone:sdk:response", response)
		return
	end

	local ok, result, dispatchError = pcall(function()
		return DispatchProvider(
			manifest,
			controller,
			tostring(request.action or "open"),
			type(request.payload) == "table" and request.payload or {},
			type(request.context) == "table" and request.context or {}
		)
	end)

	if not ok then
		response.error = "provider_failed"
		response.details = tostring(result)
	elseif result == nil then
		response.error = tostring(dispatchError or "empty_response")
	else
		response.ok = type(result) ~= "table" or result.ok ~= false
		response.data = result
		if type(result) == "table" and result.error then response.error = tostring(result.error) end
	end

	TriggerClientEvent(controller, "m-phone:sdk:response", response)
end)

exports("m-phone", "RegisterApp", function(manifest)
	return SDK.RegisterApp(manifest)
end)

exports("m-phone", "GetRegisteredApps", function()
	local result = {}
	for _, manifest in pairs(SDK.apps) do result[#result + 1] = Shared.CopyPublicManifest(manifest) end
	return result
end)

local configuredApps = Config and Config.SDK and Config.SDK.Apps
if type(configuredApps) == "table" then
	for _, appConfig in ipairs(configuredApps) do
		if EntryEnabled(appConfig) then
			local manifestModule = type(appConfig) == "table" and tostring(appConfig.Manifest or "") or ""
			local serverModule = type(appConfig) == "table" and tostring(appConfig.Server or "") or ""
			if manifestModule ~= "" then
				local manifestOk, manifest = pcall(require, manifestModule)
				if manifestOk then
					local registered = SDK.RegisterApp(manifest)
					if registered and serverModule ~= "" then
						local serverOk, provider = pcall(require, serverModule)
						if serverOk and type(provider) == "table" and type(provider.HandleRequest) == "function" then
							SDK.RegisterBuiltinHandler(manifest.id, provider.HandleRequest)
						else
							print(("[m-phone][SDK][server] failed to load provider %s: %s"):format(serverModule, tostring(provider)))
						end
					end
				else
					print(("[m-phone][SDK][server] failed to load manifest %s: %s"):format(manifestModule, tostring(manifest)))
				end
			end
		end
	end
end

return SDK
