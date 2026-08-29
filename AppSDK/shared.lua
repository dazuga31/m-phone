local Shared = {}

local APP_ID_PATTERN = "^[a-z0-9][a-z0-9%._%-]+$"
local PACKAGE_PATTERN = "^[A-Za-z0-9][A-Za-z0-9_%-]+$"

local function SafeString(value, fallback, maxLength)
	local result = tostring(value or fallback or "")
	if maxLength and #result > maxLength then
		result = string.sub(result, 1, maxLength)
	end
	return result
end

local function CopyStringArray(value)
	local result = {}
	if type(value) ~= "table" then return result end
	for _, entry in ipairs(value) do
		local normalized = SafeString(entry, "", 80)
		if normalized ~= "" then result[#result + 1] = normalized end
	end
	return result
end

function Shared.NormalizeManifest(input)
	if type(input) ~= "table" then return nil, "manifest_invalid" end

	local id = string.lower(SafeString(input.id, "", 96))
	if id == "" or not string.match(id, APP_ID_PATTERN) then
		return nil, "app_id_invalid"
	end

	local provider = SafeString(input.provider or input.package, "", 80)
	if provider == "" or not string.match(provider, PACKAGE_PATTERN) then
		return nil, "provider_invalid"
	end

	local web = type(input.web) == "table" and input.web or {}
	local entry = SafeString(web.entry or input.entry, "", 240)
	entry = string.gsub(entry, "\\", "/")
	entry = string.gsub(entry, "^/+", "")
	if entry == "" or string.find(entry, "..", 1, true) then
		return nil, "web_entry_invalid"
	end

	local icon = SafeString(input.icon, "", 240)
	icon = string.gsub(icon, "\\", "/")
	icon = string.gsub(icon, "^/+", "")

	local surfaces = type(input.surfaces) == "table" and input.surfaces or {}
	local manifest = {
		id = id,
		sdkVersion = math.max(1, math.floor(tonumber(input.sdkVersion) or 1)),
		version = SafeString(input.version, "1.0.0", 32),
		label = SafeString(input.label, id, 64),
		description = SafeString(input.description, "", 240),
		developer = SafeString(input.developer, provider, 64),
		provider = provider,
		icon = icon,
		web = {
			entry = entry,
			mode = "sandboxed",
		},
		surfaces = {
			phone = surfaces.phone ~= false,
			desktop = surfaces.desktop == true,
			tablet = surfaces.tablet == true,
			pos = surfaces.pos == true,
		},
		installable = input.installable ~= false,
		defaultInstalled = input.defaultInstalled == true,
		category = SafeString(input.category, "other", 32),
		permissions = CopyStringArray(input.permissions),
		order = tonumber(input.order) or 900,
		serverExport = SafeString(input.serverExport, "HandleMPhoneRequest", 64),
	}

	manifest.web.url = "http://localhost:12890/" .. provider .. "/" .. entry
	if icon ~= "" then
		manifest.iconUrl = "http://localhost:12890/" .. provider .. "/" .. icon
	else
		manifest.iconUrl = ""
	end

	return manifest
end

function Shared.CopyPublicManifest(manifest)
	return {
		id = manifest.id,
		sdkVersion = manifest.sdkVersion,
		version = manifest.version,
		label = manifest.label,
		description = manifest.description,
		developer = manifest.developer,
		provider = manifest.provider,
		iconUrl = manifest.iconUrl,
		web = {
			url = manifest.web.url,
			mode = "sandboxed",
		},
		surfaces = manifest.surfaces,
		installable = manifest.installable,
		defaultInstalled = manifest.defaultInstalled,
		category = manifest.category,
		permissions = manifest.permissions,
		order = manifest.order,
	}
end

function Shared.ResolveControllerAndPayload(a, b)
	local controller = a
	local payload = b
	if type(a) ~= "userdata" and type(a) ~= "number" then
		controller = source
		payload = a
	end
	if type(payload) ~= "table" then payload = {} end
	return controller, payload
end

return Shared
