# Phone App Template

Copy this folder when creating a sandboxed custom Phone App.

1. Rename the folder.
2. Change `id`, metadata, `provider`, `icon`, and `web.entry` in `manifest.lua`.
3. Keep `surfaces.phone = true`; enable other surfaces only after testing their layouts.
4. Register the manifest in both client and server runtime through the App SDK.
5. Implement trusted requests in `server.lua` and presentation in `web/`.

The template deliberately uses plain HTML, CSS, and JavaScript. Bundled frameworks are allowed as long as the built files remain provider-relative and work inside the sandboxed frame.

See [../../AppSDK/README.md](../../AppSDK/README.md) and [../../CUSTOM_APPS.md](../../CUSTOM_APPS.md).
