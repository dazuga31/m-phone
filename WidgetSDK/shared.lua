local Shared = {}

local ID_PATTERN = "^[a-z0-9][a-z0-9%._%-]+$"
local PACKAGE_PATTERN = "^[A-Za-z0-9][A-Za-z0-9_%-]+$"
local VALID_SIZE = { minimal = true, medium = true, wide = true }
local LEGACY_SIZE = { small = "minimal", large = "wide" }
local VALID_SURFACE = { phone = true, tablet = true, desktop = true }

local function Text(value, fallback, limit)
	local result = tostring(value or fallback or "")
	if limit and #result > limit then result = string.sub(result, 1, limit) end
	return result
end

local function Sizes(value)
	local result = {}
	if type(value) == "table" then
		for _, size in ipairs(value) do
			size = string.lower(Text(size, "minimal", 16))
			size = LEGACY_SIZE[size] or size
			if VALID_SIZE[size] then result[#result + 1] = size end
		end
	end
	if #result == 0 then result[1] = "minimal" end
	return result
end

local function Strings(value)
	local result = {}
	if type(value) == "table" then
		for _, entry in ipairs(value) do
			entry = Text(entry, "", 80)
			if entry ~= "" then result[#result + 1] = entry end
		end
	end
	return result
end

local function Surfaces(value)
	local result = { phone = true, tablet = false, desktop = false }
	if type(value) ~= "table" then return result end
	for surface in pairs(VALID_SURFACE) do result[surface] = value[surface] == true end
	return result
end

function Shared.NormalizeManifest(input)
	if type(input) ~= "table" then return nil, "manifest_invalid" end
	local id = string.lower(Text(input.id, "", 96))
	if id == "" or not string.match(id, ID_PATTERN) then return nil, "widget_id_invalid" end
	local provider = Text(input.provider or input.package, "", 80)
	if provider == "" or not string.match(provider, PACKAGE_PATTERN) then return nil, "provider_invalid" end
	local web = type(input.web) == "table" and input.web or {}
	local entry = string.gsub(string.gsub(Text(web.entry or input.entry, "", 240), "\\", "/"), "^/+", "")
	if entry == "" or string.find(entry, "..", 1, true) then return nil, "web_entry_invalid" end
	local sizes = Sizes(input.sizes)
	local defaultSize = string.lower(Text(input.defaultSize, sizes[1], 16))
	defaultSize = LEGACY_SIZE[defaultSize] or defaultSize
	if not VALID_SIZE[defaultSize] then defaultSize = sizes[1] end
	local manifest = {
		id = id,
		sdkVersion = math.max(1, math.floor(tonumber(input.sdkVersion) or 1)),
		version = Text(input.version, "1.0.0", 32),
		label = Text(input.label, id, 64),
		description = Text(input.description, "", 240),
		developer = Text(input.developer, provider, 64),
		provider = provider,
		web = { entry = entry, mode = "sandboxed" },
		sizes = sizes,
		defaultSize = defaultSize,
		defaultEnabled = input.defaultEnabled == true,
		surfaces = Surfaces(input.surfaces),
		permissions = Strings(input.permissions),
		order = tonumber(input.order) or 900,
		serverExport = Text(input.serverExport, "HandleMPhoneWidgetRequest", 64),
	}
	manifest.web.url = "http://localhost:12890/" .. provider .. "/" .. entry
	return manifest
end

function Shared.CopyPublicManifest(manifest)
	return {
		id = manifest.id, sdkVersion = manifest.sdkVersion, version = manifest.version,
		label = manifest.label, description = manifest.description, developer = manifest.developer,
		provider = manifest.provider, web = { url = manifest.web.url, mode = "sandboxed" },
		sizes = manifest.sizes, defaultSize = manifest.defaultSize,
		defaultEnabled = manifest.defaultEnabled, surfaces = manifest.surfaces,
		permissions = manifest.permissions, order = manifest.order,
	}
end

function Shared.ResolveSurface(context)
	local surface = string.lower(Text(type(context) == "table" and context.surface or "phone", "phone", 16))
	if not VALID_SURFACE[surface] then return "phone" end
	return surface
end

function Shared.SupportsSurface(manifest, context)
	local surfaces = type(manifest) == "table" and manifest.surfaces or nil
	return type(surfaces) == "table" and surfaces[Shared.ResolveSurface(context)] == true
end

function Shared.ResolveControllerAndPayload(a, b)
	local controller, payload = a, b
	if type(a) ~= "userdata" and type(a) ~= "number" then controller, payload = source, a end
	if type(payload) ~= "table" then payload = {} end
	return controller, payload
end

return Shared
