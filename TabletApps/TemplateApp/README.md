# Tablet App Template

Copy this folder when creating a sandboxed custom Tablet App.

1. Rename the folder and choose a unique lowercase `id`.
2. Update `provider`, `icon`, and `web.entry` in `manifest.lua`.
3. Keep `surfaces.tablet = true` and design for the full Tablet workspace.
4. Register the same manifest on client and server.
5. Keep gameplay mutations in a validated server handler.

Tablet installation and layout state are independent from Phone. Do not reuse a narrow Phone layout without a responsive Tablet design.

See [../../AppSDK/README.md](../../AppSDK/README.md) and [../../CUSTOM_APPS.md](../../CUSTOM_APPS.md).
