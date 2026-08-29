# Phone Widget Template

Copy this folder when creating a custom Phone widget.

1. Rename the folder and update the unique `id` in `manifest.lua`.
2. Update `provider` and `web.entry`.
3. Declare only implemented sizes: `minimal`, `medium`, and/or `wide`.
4. Keep `surfaces.phone = true`.
5. Register `manifest.lua`, `client.lua`, and `server.lua` in `Config.WidgetSDK.Widgets`.
6. Implement size-aware presentation in `web/`.

Use `client.lua` for safe local data and `server.lua` for authoritative data or actions. The host passes current size, language, and surface with each request.

See [../../WidgetSDK/README.md](../../WidgetSDK/README.md) and [../../CUSTOM_WIDGETS.md](../../CUSTOM_WIDGETS.md).
