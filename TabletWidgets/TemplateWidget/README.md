# Tablet Widget Template

This folder is a copy-ready example for a custom `m-phone` Tablet widget.

1. Copy `TabletWidgets/TemplateWidget` and rename the folder.
2. Change `id`, `label`, `developer`, `provider`, `web.entry`, and `order` in `manifest.lua`.
3. Keep `surfaces.tablet = true`; enable another surface only when its layout is supported.
4. Register the copied manifest and handlers in `Config.WidgetSDK.Widgets`.
5. Implement local data in `client.lua`, trusted operations in `server.lua`, and presentation in `web/`.

The host sends `size`, `language`, and `surface` in every request context. Server-side handlers must validate all gameplay-affecting operations.
