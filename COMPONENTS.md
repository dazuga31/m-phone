# m-phone component map

`m-phone` contains the shared Phone/Tablet renderer and several presentation modules. Gameplay domains should remain separate resources and expose exports consumed by device Apps.

## Core runtime

- `client.lua` - HELIX WebUI lifecycle, input, device state, and browser bridge.
- `server.lua` - language, notifications, compatibility wrappers, and trusted request routing.
- `config.lua` - feature flags, providers, commerce map selection, App SDK, and Widget SDK registration.
- `web/` - compiled production renderer; React/TypeScript source is distributed separately.

## Extension SDKs

- `AppSDK/` - manifest validation, App registry, sandboxed request routing.
- `WidgetSDK/` - manifest validation, size/surface routing, client/server data handlers.
- `PhoneApps/` and `TabletApps/` - device-specific App implementations and templates.
- `PhoneWidgets/` and `TabletWidgets/` - device-specific Widget implementations and templates.

Phone and Tablet share registries but are isolated through manifest `surfaces`. Content is never copied to Tablet merely because it supports Phone.

## Other surfaces

- `Desktop/` - transitional callback-registry bridge only; spatial rendering, world profiles, interactions and HMap markers live in `m-desktop`.
- `PosApps/` - point-of-sale and kiosk presentation.
- `WorldSystems/` - device-adjacent world interactions such as the parking meter.

Desktop-only Lua presentation modules now live in `m-desktop/DesktopApps/`.
The compiled browser bundle remains temporarily hosted by `m-phone/web/` and
is accessed through the narrow client UI bridge documented in [API.md](API.md).

## Service boundaries

- `Integrations/` - thin adapters to authoritative external resources.
- `Services/` - shared device-facing helpers such as reward presentation.
- `db/` and `storage/` - phone-owned persistence only.

Authoritative banking, business, courier, jobs, trucker, properties, documents, inventory, and vehicle logic must live in their corresponding `m-*` resource. Device Apps consume exports/events and must not query another resource's database directly.

## Public documentation

- [API.md](API.md)
- [EXPORTS.md](EXPORTS.md)
- [CUSTOM_APPS.md](CUSTOM_APPS.md)
- [CUSTOM_WIDGETS.md](CUSTOM_WIDGETS.md)
- [DEPENDENCIES.md](DEPENDENCIES.md)
