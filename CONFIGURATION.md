# m-phone configuration

The public runtime configuration is stored in `config.lua`. The compiled WebUI must not be edited to configure integrations.

## Core and inventory

```lua
Config.Use.Core = "qb"
Config.Inventory = "auto" -- auto, none, m-inventory, qb-inventory, hl-inventory
Config.Use.Bank = "qb" -- "qb" or "mbank"
Config.LegacyLocalDomainSchema = false
Config.Banking.Resource = "m-banking"
Config.Trucker.Resource = "m-trucker"
Config.Business.Resource = "m-business"
Config.Jobs.Resource = "m-jobs"
```

`qb` reads and updates the standard `qb-core` `money.bank` and `money.cash`
values. It supports balances, deposits, withdrawals, debits, credits, and
transfers to online players. `qb-core` has no authoritative bank ledger, so
transaction history and recent recipients are empty in this mode.

`mbank` delegates the complete banking API to the resource configured by
`Config.Banking.Resource`. Use it for persistent accounts, transaction history,
and recipients when `m-banking` is installed.

Start every package listed in `Config.Dependencies.Required` before `m-phone`.
Device Apps use these resource adapters and must not call qb-core or domain
SQLite tables directly.

`m-core` is a reserved configuration value only. The public runtime currently
implements the `qb` core adapter; do not select `m` until an m-core provider is
available.

## Features

Every bundled integration can be disabled independently through `Config.Features`.

```lua
Config.Features = {
    Phone = true,
    Desktop = false,
    Tablet = false,
    POS = false,
    Camera = true,
    Gallery = true,
    Bank = true,
    Trucker = false,
    Courier = false,
    Garage = false,
    Parking = true,
    ParkingMeter = false,
    CitizenServices = false,
    PropertyMarket = false,
    FurnitureStore = false,
    ShopManager = false,
    JobCentre = false,
    Rewards = false,
    CreatorLink = false,
}
```

This is the safe clean-QB baseline shipped by default. Disabled feature modules
are not loaded. Disabled Desktop Apps are also removed from terminal
`allowedApps` lists at runtime.

## Item images

Item artwork is provided by the configured inventory package. It is not duplicated in the `m-phone` WebUI.

```lua
Config.InventoryImages = {
    Provider = "auto",
    AutoFallback = "qb-inventory",
    BaseUrl = "",
    Extension = ".png",
    FallbackUrl = "",
    Overrides = {
        -- custom_item = "https://example.invalid/custom_item.png",
    },
}
```

With `Provider = "auto"`, `m-phone` uses the `m-inventory` runtime marker when
that integration is already running. Otherwise it uses `AutoFallback`, which is
`qb-inventory` in the clean-QB profile. HELIX export proxies cannot reliably
prove that a package is installed, so select `Provider` explicitly when using a
different inventory implementation. Provider-specific WebUI paths are
configured under `Config.InventoryImages.Providers`.

Keep `Config.LegacyLocalDomainSchema = false` for new installations. Set it to
`true` only while migrating an old all-in-one build that still reads local
Shop, Courier, or Trucker tables. Existing legacy tables are never deleted.

The WebUI tries `clothing/<itemId>.png`, then `<itemId>.png`, followed by `FallbackUrl`. Absolute HTTP, data, and blob URLs supplied by an App remain supported.

## Map profile

`Config.ActiveMap` selects the coordinate profile:

```lua
Config.ActiveMap = "TEST_MAP" -- TEST_MAP or PACIFICA_MAP
```

`TEST_MAP` is intentionally included for HELIX Studio App development. Test-only privileged actions must still be protected server-side.

## Optional integrations

`Config.Dependencies.Optional` documents which features use another package. Missing optional packages should affect only those features. Disable the corresponding feature when the integration is not installed.

`CitizenServices`, `ParkingMeter`, and CreatorLink item rewards currently use
the transactional `m-inventory` API. CreatorLink cash rewards do not need an
inventory provider when no item rewards are configured.

The server prints one startup line for every required and optional dependency
using the prefix `[m-phone][dependency]`. These lines report configuration, not
an unreliable availability claim based on HELIX export proxies.

## Camera storage secrets

Public camera settings remain in `config.lua`, while server-only endpoints and
credentials belong in:

```text
PhoneApps/Camera/camera_storage_local.lua
```

Create it from `camera_storage_local.example.lua`. The local file is ignored by
Git and overrides the safe defaults from `camera_storage_server.lua`.

## Developer operations

`TEST_MAP` does not automatically enable privileged test operations. Test payouts and test debits require both switches:

```lua
Debug = true
Config.Developer.AllowTestMutations = true
```

Keep both disabled in every public or production World.
