local settings = {
	CustomBaseUrl = "",
	CustomInternalBaseUrl = "",
	CustomApiKey = "",
	FiveManageApiKey = "",
}

local ok, localSettings = pcall(require, "PhoneApps.Camera.camera_storage_local")
if ok and type(localSettings) == "table" then
	for key, value in pairs(localSettings) do
		settings[key] = value
	end
end

return settings
