# Installing m-phone

## GitHub installation

1. Download the latest source archive or clone the repository.
2. Place it in the World scripts directory using the exact folder name `m-phone`.
3. Add every required package from `DEPENDENCIES.md` before `m-phone`.
4. Add optional integration packages used by enabled Apps.
5. Review `config.lua`, especially `Config.Features`, `Config.ActiveMap`, and `Config.InventoryImages`.
6. Start the World and inspect `[m-phone][dependency]` startup messages.

The repository already contains the production WebUI in `web/`. Node.js, npm,
React source, and a local WebUI build are not required for installation.

## Camera storage

Camera credentials are never stored in the tracked configuration. To configure
remote photo uploads:

1. Copy `PhoneApps/Camera/camera_storage_local.example.lua` to
   `PhoneApps/Camera/camera_storage_local.lua`.
2. Replace `CHANGE_KEY` with the API key configured by your photo service.
   The value on both services must match exactly.
3. Keep the local file out of source control. It is covered by `.gitignore`.

`CHANGE_KEY` is only a placeholder and must never be used as a production key.
After cloning or updating the repository, do not edit the tracked example with
your real secret; place it only in `camera_storage_local.lua`.

If camera storage is not configured, disable Camera uploads through the feature
configuration until a provider is available.

## HELIX Studio quick start

Use the shared test profile:

```lua
Config.ActiveMap = "TEST_MAP"
```

`TEST_MAP` contains development terminals and interaction points intended for App testing. Privileged debug actions are not enabled by the map profile alone.

## Item artwork

The default `auto` mode uses `m-inventory` when its runtime marker is available,
then falls back to `qb-inventory`. HELIX export proxies do not provide reliable
package discovery. To use another package, no inventory, or a CDN, set
`Config.InventoryImages.Provider` (`none` is supported) and `BaseUrl`
explicitly. See `CONFIGURATION.md` for overrides and fallback behavior.

## First-run checks

- The Phone opens only when `Config.Features.Phone` is enabled.
- Desktop terminals expose only enabled Apps.
- Startup dependency lines distinguish configured and inactive integrations; they do not probe HELIX export proxies.
- A missing provider affects only the enabled App that calls it, not the base Phone runtime.
- Item images load from the configured inventory provider.
