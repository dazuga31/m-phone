local Shared = require("AppSDK.shared")

local SDK = {
	apps = {},
	ui = nil,
}

local function Enabled()
	return Config and Config.SDK and Config.SDK.Enabled ~= false
end

local function EntryEnabled(entry)
	local feature = type(entry) == "table" and tostring(entry.Feature or "") or ""
	return feature == "" or not Config or not Config.IsFeatureEnabled or Config.IsFeatureEnabled(feature)
end

local function PublicApps()
	local result = {}
	for _, manifest in pairs(SDK.apps) do
		result[#result + 1] = Shared.CopyPublicManifest(manifest)
	end
	table.sort(result, function(left, right)
		if left.order == right.order then return left.id < right.id end
		return left.order < right.order
	end)
	return result
end

local function RegistryPayload()
	return {
		sdkVersion = tonumber(Config and Config.SDK and Config.SDK.Version) or 1,
		apps = PublicApps(),
	}
end

local function PushRegistry()
	if not SDK.ui then return end
	SDK.ui:SendEvent("sdk:registry", RegistryPayload())
end

function SDK.RegisterApp(input)
	if not Enabled() then return false, "sdk_disabled" end
	local manifest, err = Shared.NormalizeManifest(input)
	if not manifest then return false, err end
	local supportedVersion = tonumber(Config and Config.SDK and Config.SDK.Version) or 1
	if manifest.sdkVersion > supportedVersion then return false, "sdk_version_unsupported" end
	SDK.apps[manifest.id] = manifest
	PushRegistry()
	return true, manifest.id
end

function SDK.BindUI(ui)
	SDK.ui = ui
	if not ui then return false end

	ui:RegisterEventHandler("sdk:request", function(payload, cb)
		payload = type(payload) == "table" and payload or {}
		local appId = string.lower(tostring(payload.appId or ""))
		local requestId = tostring(payload.requestId or "")
		if requestId == "" or not SDK.apps[appId] then
			if cb then cb({ ok = false, error = "sdk_request_invalid" }) end
			return
		end

		TriggerServerEvent("m-phone:sdk:request", {
			requestId = requestId,
			appId = appId,
			action = tostring(payload.action or "open"),
			payload = type(payload.payload) == "table" and payload.payload or {},
			context = type(payload.context) == "table" and payload.context or {},
		})

		if cb then cb({ ok = true, accepted = true, requestId = requestId }) end
	end)

	ui:RegisterEventHandler("sdk:getRegistry", function(_, cb)
		local registry = RegistryPayload()
		PushRegistry()
		if cb then cb(registry) end
	end)

	PushRegistry()
	return true
end

RegisterClientEvent("m-phone:sdk:response", function(payload)
	if SDK.ui then SDK.ui:SendEvent("sdk:response", type(payload) == "table" and payload or {}) end
end)

exports("m-phone", "RegisterApp", function(manifest)
	return SDK.RegisterApp(manifest)
end)

exports("m-phone", "GetRegisteredApps", function()
	return PublicApps()
end)

local configuredApps = Config and Config.SDK and Config.SDK.Apps
if type(configuredApps) == "table" then
	for _, appConfig in ipairs(configuredApps) do
		if EntryEnabled(appConfig) then
			local manifestModule = type(appConfig) == "table" and tostring(appConfig.Manifest or "") or ""
			if manifestModule ~= "" then
				local ok, manifest = pcall(require, manifestModule)
				if ok then
					local registered, result = SDK.RegisterApp(manifest)
					print(("[m-phone][SDK][client] app %s: %s"):format(manifestModule, registered and "registered" or tostring(result)))
				else
					print(("[m-phone][SDK][client] failed to load manifest %s: %s"):format(manifestModule, tostring(manifest)))
				end
			end
		end
	end
end

return SDK
