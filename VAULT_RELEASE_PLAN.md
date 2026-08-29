# m-phone - Historical Vault Release Plan

> Historical planning note: this file is retained as architecture history.
> Current GitHub installation, dependency, security, and release requirements
> are authoritative in [README.md](README.md),
> [INSTALLATION.md](INSTALLATION.md), and the linked public documentation.

## 1. Goal

Publish `m-phone` in HELIX Vault as a free, production-ready script package with a compiled WebUI, documented integration points, and templates for creating Phone, Desktop, Tablet, POS, and other device applications.

The release package must be usable without access to the private TypeScript/React source of the main `m-phone` WebUI. Third-party application development must happen through a documented SDK and public extension API rather than by modifying the `m-phone` core bundle.

## 2. Product Scope

The first public release includes:

- Phone shell and bundled first-party Phone Apps.
- A temporary compiled Desktop browser host used by the separate `m-desktop` resource.
- Tablet, POS, kiosk, and device surfaces supported by the runtime.
- Shared language and settings state across supported devices.
- Database initialization and automatic compatible schema updates.
- Compiled production WebUI without source maps or TypeScript/React source files.
- Public Lua exports, events, payload contracts, and App SDK documentation.
- `TEST_MAP` profile for HELIX Studio and community App development.
- Pacifica profile as an additional example/profile where applicable.

## 3. Supported Environment

`m-phone` is not standalone in the first public release.

### Required dependencies

- `qb-core`
- `m-inventory`
- Other required `m-*` and `hl-*` packages used by enabled bundled Apps

All required packages must be published in Vault and declared as package dependencies.

Missing optional integrations must disable only the affected App or feature. They must not prevent the phone shell, settings, language selection, or unrelated Apps from loading.

Support for replacing `qb-core` with another framework is postponed. A later release may move all framework calls into a dedicated adapter file where server owners can replace money, player, metadata, and database operations.

## 4. TEST_MAP Policy

`TEST_MAP` remains included and may remain the default profile because every HELIX Studio user has access to the shared testing environment.

Its purpose is to let users:

- Test the complete package immediately after installation.
- Develop and verify custom Phone/Desktop/Tablet/POS Apps.
- Test interactions, markers, terminals, ATMs, stores, and service points.
- Reproduce bugs using shared coordinates.

Test-only money manipulation, debug RPCs, administrator actions, and unsafe server events are not part of this policy. Such functionality must still be removed from production or protected by both `Config.Debug` and a server-side administrator permission check.

## 5. WebUI Distribution Boundary

The Vault archive contains only the compiled WebUI:

```text
m-phone/web/index.html
m-phone/web/assets/*.js
m-phone/web/assets/*.css
m-phone/web/assets/<required m-phone media>
```

The archive must not contain:

- `src/`
- React/TypeScript source files
- `_mock/`
- `node_modules/`
- source maps
- build logs
- local development scripts
- screenshots or photos generated during testing
- API keys, tokens, webhook URLs, or private endpoints

Compilation/minification is not treated as a security boundary. All sensitive validation and authoritative state changes must remain server-side.

## 6. Image and Media Strategy

`m-phone` must not bundle the complete item-image catalog. The current duplicated inventory image collection should be removed from the production WebUI.

### Default provider

The default item-image provider is `m-inventory`.

Expected public URL format:

```text
/m-inventory/web/assets/items/<itemId>.png
```

The exact final path must be centralized in one resolver and documented by both packages.

### Custom inventory support

Configuration must allow another inventory/image provider:

```lua
Config.Inventory = {
    Provider = "m-inventory",
    ImageBaseUrl = "/m-inventory/web/assets/items/",
    ImageExtension = ".png",
    FallbackImage = "/m-phone/web/assets/item-placeholder.png",
}
```

Supported approaches:

1. A configurable static `ImageBaseUrl`.
2. An optional inventory export that resolves an item image URL.
3. A server-defined item-to-image override map for exceptional items.

`m-phone` keeps only its own media:

- App icons.
- Phone/device visual assets.
- Desktop and system icons.
- Job Centre gallery assets owned by `m-phone`.
- Required backgrounds and placeholders.

## 7. Configuration Target

Public configuration must clearly separate:

```text
Core
Inventory
Features
Map profile
Phone settings
Desktop settings
Apps
Camera storage
Markers and interactions
Developer options
```

Minimum feature switches:

```lua
Config.Features = {
    Phone = true,
    Desktop = true,
    Tablet = false,
    POS = true,
    Camera = true,
    Gallery = true,
    Bank = true,
    Trucker = true,
    Courier = true,
    Garage = true,
    CitizenServices = true,
    PropertyMarket = true,
    FurnitureStore = true,
}
```

Server-only credentials must live in a separate ignored local configuration file or environment-backed configuration. The package includes only an example file.

## 8. Public App Extension Model

Third-party Apps must not require editing the compiled `m-phone` WebUI.

The target API provides registration for:

- Phone Apps
- Desktop Apps
- Tablet Apps
- POS/Kiosk Apps
- Other future device surfaces

Target registration example:

```lua
exports["m-phone"]:RegisterApp({
    id = "example.notes",
    device = "phone",
    title = "Notes",
    icon = "/example-notes/web/icon.png",
    entrypoint = "/example-notes/web/index.html",
    version = "1.0.0",
    permissions = {
        "notifications",
        "player.identity",
    },
})
```

Required lifecycle/API concepts:

- Register and unregister App.
- Install and uninstall App.
- Open, close, focus, and background lifecycle.
- Namespaced WebUI-to-Lua and Lua-to-WebUI messages.
- Locale and theme updates.
- Phone notification/Peek API.
- GPS and map request API.
- Permission declarations.
- Version and compatibility checks.
- Graceful handling when the external App package is missing.

Before final implementation, create a small prototype to verify that a separately packaged WebUI can render reliably inside an `m-phone` device surface. If embedded external WebUI is not supported reliably, use schema-driven Apps rendered by the compiled core.

## 9. TemplateApps SDK

Templates are distributed separately from the `m-phone` Vault package.

Target SDK structure:

```text
m-phone-sdk/
├── docs/
├── shared/
├── phone-app-template/
├── desktop-app-template/
├── tablet-app-template/
├── pos-app-template/
├── schema-app-template/
└── examples/
```

Each template includes:

- Its own `package.json`.
- Independent Vite/React build where required.
- Lua client/server bridge examples.
- App manifest.
- English and Ukrainian language files.
- Mock data for browser development.
- Production build command.
- Correct Vault-compatible WebUI path.
- One complete working example.

## 10. Security Requirements

Before publication:

- Rotate every secret that has ever existed in the repository/package.
- Remove hard-coded API credentials.
- Remove or protect test money events.
- Validate all purchases, transfers, rewards, jobs, documents, and ownership changes server-side.
- Never trust player ID, price, balance, ownership, job, rank, or item metadata sent by WebUI/client.
- Add rate limits/cooldowns to sensitive RPCs.
- Namespace every third-party App event.
- Reject undeclared App permissions.
- Avoid exposing database paths or raw database errors to clients.

## 11. Documentation Set

The public release requires:

```text
README.md
INSTALLATION.md
CONFIGURATION.md
DEPENDENCIES.md
APP_DEVELOPMENT.md
EVENTS.md
EXPORTS.md
DATABASE.md
MIGRATION.md
SECURITY.md
TROUBLESHOOTING.md
CHANGELOG.md
LICENSE
```

Documentation must cover:

- Installation from Vault.
- Required dependency order.
- TEST_MAP quick start.
- Custom map profiles.
- Inventory image providers.
- Camera/photo storage setup.
- Database creation and upgrades.
- Device and App feature switches.
- External App registration.
- Lua/WebUI payload contracts.
- Version compatibility.
- Known Closed Alpha limitations.

## 12. Release Package Layout

Target archive:

```text
m-phone.zip
├── package.json
├── config.lua
├── client.lua
├── server.lua
├── client_shared.lua
├── server_shared.lua
├── server_helpers.lua
├── db.lua
├── Apps/
├── Desktop/
├── Extras/
├── Markers/
├── web/
├── README.md
├── CHANGELOG.md
├── LICENSE
└── documentation files
```

The archive must not contain runtime-generated storage or developer artifacts.

## 13. Implementation Phases

### Phase 1 — Release sanitation

- Remove duplicated item images.
- Remove runtime-generated photos.
- Remove all secrets and rotate existing credentials.
- Protect/remove unsafe debug and test server events.
- Add release/dev configuration separation.
- Add version metadata, license, changelog, and release README.

### Phase 2 — Dependency readiness

- Publish required dependencies to Vault.
- Declare exact dependency versions.
- Add startup dependency diagnostics.
- Make optional App integrations fail gracefully.
- Document supported `qb-core` and inventory versions.

### Phase 3 — Item image provider

- Implement the centralized item-image resolver.
- Add `m-inventory` default provider.
- Add custom URL/provider configuration.
- Add placeholder behavior.
- Test missing and malformed item images.

### Phase 4 — Public extension API

- Define App manifest schema.
- Implement registration and lifecycle exports/events.
- Implement permissions and namespaces.
- Prototype external WebUI embedding.
- Select external-WebUI or schema-driven production path.

### Phase 5 — SDK and documentation

- Create all TemplateApps.
- Create one complete external App example.
- Document all exports, events, payloads, and permissions.
- Add browser development workflow.

### Phase 6 — Quality gate

- Fresh database installation.
- Upgrade from an older database.
- Missing optional dependencies.
- Two or more simultaneous players.
- Reconnect and resource restart.
- Dedicated server test.
- TEST_MAP full flow.
- English and Ukrainian UI review.
- Security abuse tests.
- Final archive content and size audit.

### Phase 7 — Vault alpha release

- Package type: `Script`.
- Slug: `m-phone`.
- Visibility: `Public`.
- Price: `Free`.
- Initial version: `0.9.0-alpha`.
- Add preview images and a short demonstration video.
- Clearly document HELIX Closed Alpha limitations.
- Avoid stability/backward-compatibility guarantees until `1.0.0`.

## 14. Definition of Done

The Vault release is ready when:

- No secret or private generated data is present in the ZIP.
- The package installs from Vault with declared dependencies.
- TEST_MAP works immediately after installation.
- Core devices still load when an optional integration is unavailable.
- Item images resolve from `m-inventory` without duplication.
- Custom inventory image paths are supported.
- The compiled WebUI contains no source maps or source tree.
- Public exports/events and payloads are documented.
- At least one external TemplateApp works without modifying `m-phone` source.
- Database migration and clean-install tests pass.
- Sensitive actions are authoritative and validated server-side.
- The final package size is reasonable and reproducible.
