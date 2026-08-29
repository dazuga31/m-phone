# m-phone architecture and extraction plan

## Goal

`m-phone` should be a Phone/Tablet device host, not a replacement for a gameplay core.
It should own Phone, Tablet and POS presentation, App/Widget SDKs, device input,
notifications and saved device preferences. Desktop world presentation belongs
to `m-desktop`. Gameplay domains
should live in independent resources and expose stable APIs to their Apps.

This cleanup changes module names and locations only. Existing events, exports,
database behavior and WebUI behavior must remain compatible.

## Current package layout

```text
m-phone/
  PhoneApps/          First-party Phone Apps and Phone templates
  TabletApps/         Tablet-only Apps and templates
  PhoneWidgets/       Phone-only Widgets and template
  TabletWidgets/      Tablet-only Widgets and template
  Desktop/            Transitional compiled-browser callback bridge only
  PosApps/            Point-of-sale Apps
  AppSDK/             Sandboxed App registration and request bridge
  WidgetSDK/          Sandboxed Widget registration and request bridge
  WorldSystems/       Physical world devices currently shipped with m-phone
  Services/           Temporary shared services awaiting extraction
  db/                 Domain persistence modules
  web/                Compiled React host
```

React already follows the same surface split under
`src/components/phone`, `src/components/tablet` and
`src/components/desktop`. It should not be reorganized merely to mirror Lua
when the existing component boundary is already clear.

## What remains in m-phone

- Phone, Tablet and POS shells plus the temporary compiled Desktop browser bundle and callback registry.
- Core Phone communications: phone numbers, contacts, SMS, calls, call history and voice routing.
- App and Widget registries, sandbox hosts and browser SDK bridges.
- Device open/close, focus, input and animation lifecycle.
- Home screen, lock screen, App layout, Widget layout and device preferences.
- Phone notifications and surface navigation.
- Thin adapters that call external domain exports.
- Compatibility exports under the existing `m-phone` resource name.

## What should leave m-phone

| Priority | Proposed resource | Current ownership inside m-phone | Boundary |
| ---: | --- | --- | --- |
| 1 | `m-parking` | `PhoneApps/Parking`, `WorldSystems/ParkingMeter`, `db/parking.lua` | Parking zones, meters, payments, receipts and active parking sessions |
| 2 | `m-creatorlink` | `PhoneApps/CreatorLink`, `PhoneWidgets/CreatorLink` | Referral codes, creator progression, rewards and CreatorLink persistence |
| 3 | `m-banking` (**extracted**) | `PhoneApps/Bank`, legacy `db/bank.lua` compatibility | Accounts, transactions, ATM operations and banking exports |
| 4 | existing `m-documents` | `db/documents.lua`, `server_invoice_service.lua` | Document and invoice persistence; m-phone should request documents through the existing resource |
| 5 | `m-trucker` (**server extracted**) | Lightweight Phone/Tablet views remain; authoritative server and DesktopApp logic moved out | Trucker contracts, routes, progression, rewards, invoices and vehicle lifecycle |
| 6 | `m-courier` (**server extracted**) | Courier presentation remains in `PhoneApps/Courier`; authoritative server logic moved out | Courier jobs, routes, progression and invoices |
| 7 | `m-business` (**server extracted**) | Shop Manager, Kiosk and Furniture presentation remains in `m-phone`; authoritative server logic moved out | Shops, stock, POS sales, business management and furniture commerce |
| 8 | `m-jobs` (**Job Centre server extracted**) | Job Centre presentation is hosted by `m-desktop`; authoritative application logic and persistence moved out | Job applications now; job catalogue, clock-on state and dispatch-facing job data later |
| 9 | `m-media` | `PhoneApps/Camera`, `db/photos.lua` | Camera uploads, gallery storage and media provider integration |
| 10 | `m-rewards` | `Services/Rewards` | Daily rewards and reward history |

`Garage` and `PropertyMarket` should ultimately call `m-properties`,
`m-garages` and `m-vehicleshop` rather than owning copies of those domains.

## Dependency rule

```text
qb-core or future m-core
          ^
          | adapters
domain resources (m-banking, m-parking, m-trucker, ...)
          ^
          | stable exports/events
m-phone device host + first-party App/Widget presentation
```

A domain resource should not require `m-phone`. If it provides an App or
Widget, it registers that presentation through `AppSDK` or `WidgetSDK` when
`m-phone` is available. The gameplay service must continue working without a
phone UI. During the current Trucker migration, dispatch SMS and Shop Manager
supply callbacks use optional `m-phone` exports as an explicit transitional
bridge; the core Trucker contract flow remains functional without them.

## Module contract

Each extracted resource should own:

- its database tables and migrations;
- authoritative server logic;
- core-provider adapter (`qb` now, `m` placeholder later);
- documented server exports;
- optional App and Widget registration;
- tests for pure domain rules.

Public operations should return a predictable result:

```lua
{
    ok = true,
    data = {},
}

-- or

{
    ok = false,
    error = "stable_error_code",
}
```

Apps should not call qb-core directly. They call their domain service, while
the domain service uses its configured core adapter.

## Migration phases

### Phase 0 - namespace cleanup (current)

- Separate Phone, Tablet, Desktop, POS, Widgets and SDK folders.
- Update all Lua module paths and manifest WebUI paths.
- Keep runtime behavior and public API unchanged.
- Desktop world profiles, physical interactions, HMap markers and the spatial renderer have moved to `m-desktop`; `m-phone` retains only callback and legacy compatibility bridges.

### Phase 1 - make entrypoints thin

- Move chat/call request wiring out of `client.lua` and `server.lua`.
- Keep entrypoints responsible only for bootstrap, UI lifecycle and module load.
- Add a small module registry so one failed optional App does not stop the host.

### Phase 2 - extract low-coupling domains

1. Extract `m-parking`.
2. Extract `m-creatorlink`.
3. Keep the compiled Desktop browser temporarily in `m-phone`, while all
   Desktop-only Lua callbacks, adapters and spatial runtime remain in `m-desktop`.

These have the clearest data ownership and provide the fastest reduction in
`m-phone` scope.

### Phase 3 - extract shared economy domains

1. Extract `m-banking` without duplicating qb banking logic.
2. Route invoices and documents through existing `m-documents`.
3. Extract `m-trucker` first, followed by `m-courier`, `m-business` and `m-jobs` incrementally.

Current status: `m-banking`, the authoritative `m-trucker`, `m-courier` and
`m-business` servers and the Job Centre portion of `m-jobs` have been extracted.
Existing `m-phone:trucker:*`, `m-phone:courier:*`, `m-phone:shop*`,
`m-phone:kioskPay`, `m-phone:furniture:*` and `m-phone:jobcentre:*` events are
intentionally preserved for UI compatibility.
The legacy Shop schema declarations remain temporarily in `m-phone/db.lua`
until a dedicated database migration removes that compatibility copy.

### Phase 4 - internal file-size cleanup

The largest remaining files should be split only after their domain ownership
is settled. Current hotspots include:

- `db.lua`
- `client.lua` and `server.lua`

Splitting these before deciding ownership would only move mixed logic into more
files and make later extraction harder.

## Recommended next implementation

The spatial renderer and Desktop-only Lua presentation now belong to
`m-desktop` and use a narrow callback bridge instead of accessing Phone
internals. The next Desktop boundary is a dedicated compiled browser bundle;
that migration should happen only when HELIX can load it without regressing the
working shared renderer. Keep core Phone communications in `m-phone`; Calls,
Contacts, Chat and their voice routing are first-party device functionality.

Do not create a generic `m-core` from these features. Small domain resources
with one owner and one public contract are easier to test, replace and publish.
