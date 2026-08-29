# m-phone Configuration

The public runtime configuration lives in `config.lua`. Configure integrations
in Lua; do not edit the compiled files under `web/assets`.

This document describes the current `0.9.1-alpha` configuration. Values marked
as reserved are not complete runtime contracts.

## Core and provider resources

```lua
Config.Use.Core = "qb" -- qb or reserved m
Config.Use.Bank = "qb" -- qb or mbank
Config.Inventory = "auto"
Config.LegacyLocalDomainSchema = false

Config.Banking.Resource = "m-banking"
Config.Trucker.Resource = "m-trucker"
Config.Desktop.Resource = "m-desktop"
Config.Courier.Resource = "m-courier"
Config.Business.Resource = "m-business"
Config.Jobs.Resource = "m-jobs"
```

`Config.Courier.Debug` enables additional Courier adapter diagnostics and
should remain `false` outside focused development.

### Core

- `qb` is implemented and uses `qb-core` players, metadata, cash, and bank
  values.
- `m` is reserved for a future m-core adapter. Do not select it in this alpha.

### Bank

- `qb` reads and updates live qb-core `money.bank` and `money.cash`. It supports
  balances, deposits, withdrawals, credits, debits, and online-player
  transfers.
- Base qb-core has no authoritative bank ledger, so history and recent
  recipients are empty in this mode.
- `mbank` delegates to `Config.Banking.Resource` and is intended for persistent
  accounts, transaction history, and recipients.

### Legacy schema

Keep `Config.LegacyLocalDomainSchema = false` for new installations. Enable it
only while migrating an old all-in-one build that still requires m-phone-owned
Shop, Courier, or Trucker tables. Existing legacy tables are not deleted.

## Features

Every optional surface or integration has a public feature switch:

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

Disabled feature modules are not loaded. Disabled Apps are filtered from
registries and terminal allowlists. A stale request to open disabled content
should return an unavailable state instead of mounting the App.

`Config.Dependencies.Required` and `Config.Dependencies.Optional` document
runtime order. They are diagnostics and configuration metadata, not reliable
HELIX package-discovery probes. Start `qb-core` and every provider needed by an
enabled feature before `m-phone`.

## Communications

```lua
Config.Communications = {
    PhoneNumberDigits = 6,
    PhoneNumberMetadataKey = "phoneNumber",
    MaxMessageLength = 500,
    MaxContactNameLength = 48,
    MaxContacts = 250,
    MessagePageSize = 40,
    RateLimitWindowSeconds = 10,
    RateLimitMessages = 8,
    CallRingTimeoutSeconds = 30,
    Voice = {
        Enabled = true,
        Provider = "helix",
        ChannelStart = 70000,
        ChannelEnd = 79999,
    },
    SystemContacts = {
        -- { id, name, phoneNumber, category }
    },
}
```

- Generated phone numbers use `PhoneNumberDigits`.
- The number is synchronized to the configured qb-core metadata key.
- Message/contact settings are server validation limits.
- `MessagePageSize` controls paged SMS history.
- Rate limits apply per configured window.
- Voice channels must remain inside a range reserved for the Phone.
- System contacts are server-defined and should use unique ids and numbers.

Changing the number format after players exist requires a reviewed metadata and
database migration.

## Phone use and prop attachment

```lua
Config.PhoneUse = {
    Enabled = true,
    Attachment = {
        enabled = false,
        owner = "m-phone",
        slot = "phone",
        mesh = "/MProps/Items/Phone/gltf/StaticMeshes/phone_1.phone_1",
        bone = "hand_r",
        location = Vector(-8.700, -2.100, 0.900),
        rotation = Rotator(-28.000, 158.900, 9.400),
        scale = 1.000,
    },
}
```

The optional prop requires `m-attachments`. The owner and slot identify the
attachment lifecycle; mesh, bone, transform, and scale control its appearance.
Disable `Attachment.enabled` when that provider or asset is unavailable.

## Physical parking meters

`Config.ParkingMeter` controls native world-space meters:

```lua
Config.ParkingMeter = {
    Enabled = false,
    MinutesStep = 15,
    PricePerStep = 15,
    DefaultMinutes = 30,
    MaxMinutes = 240,
    Blueprint = "/MProps/Parking/ParkingPayStand/Blueprints/BP_ParkingPayStand.BP_ParkingPayStand_C",
    AutoDiscoverPlacedActors = true,
    Locations = {},
    InteractionDistance = 180,
    InteractionUiDistance = 180,
    Spatial = {
        cameraDistance = 35.0,
        cameraAxis = "right",
        cameraNormalSign = 0.0,
        cameraHeight = 0.0,
        cameraSideOffset = 0.0,
        cameraFov = 45.0,
        cameraSharpen = 1.0,
    },
}
```

- `PricePerStep` is expressed in game dollars and converted to integer pence by
  server Lua.
- `AutoDiscoverPlacedActors` connects compatible Blueprints placed in the
  World.
- `Locations` optionally defines Lua-spawned meters:

```lua
Locations = {
    {
        id = "parking_meter_0001",
        x = 100.0,
        y = 200.0,
        z = 91.65,
        pitch = 0.0,
        yaw = 90.0,
        roll = 0.0,
        defaultMinutes = 30,
        spatial = {
            cameraDistance = 35.0,
        },
    },
}
```

- `InteractionDistance` uses HELIX world units and controls nearest-meter
  discovery.
- `InteractionUiDistance` is reserved compatibility configuration in the
  current alpha; do not rely on it as a separate server security check.
- Spatial settings control only the inspection camera.
- The meter uses physical keys `1` through `4`; no cursor is required.

Parking-meter receipts require the configured banking flow, `m-inventory`, and
`m-documents`. Disable the feature if those providers are unavailable.

## Phone Parking App

Parking zones are authoritative server configuration:

```lua
Config.ParkingApp = {
    Enabled = true,
    MinutesStep = 15,
    DefaultMinutes = 30,
    MaxMinutes = 480,
    PeakPeriods = {
        { days = { 2, 3, 4, 5, 6 }, startMinute = 450, endMinute = 570 },
    },
    Zones = {
        ["0001"] = {
            label = "Central Station",
            district = "City Centre",
            pricePer15 = 225,
            weekendDiscount = 20,
            peakFee = 30,
            maxMinutes = 240,
        },
        ["0007"] = {
            label = "Community Park",
            district = "North Pacifica",
            pricePer15 = 0,
            free = true,
            maxMinutes = 240,
        },
    },
}
```

- Zone ids remain four-digit strings because players enter the printed id.
- `pricePer15` is integer cents/pence for each 15-minute step.
- `weekendDiscount` and `peakFee` are percentages.
- `free = true` creates a no-charge zone.
- Zone `maxMinutes` overrides the global maximum.
- Peak `startMinute` and `endMinute` are minutes after midnight.
- Peak `days` use Lua `os.date("*t").wday`: Sunday is `1`, Monday is `2`,
  through Saturday `7`.

The server calculates the final amount. Never accept a client-supplied price.

## App feature filtering

`Config.AppFeatures` maps compiled App ids to `Config.Features` keys.
`Config.FilterAllowedApps()` applies this mapping to terminal/App allowlists.

This is advanced internal configuration. Update it only when adding or
renaming an App id that must follow a feature switch.

## Inventory

### Runtime provider

```lua
Config.Inventory = "auto" -- auto, none, m-inventory, qb-inventory, hl-inventory
```

`Config.InventoryPriority` and `Config.InventoryItemMap` are compatibility
settings for legacy item lookup. Keep item mutations in the authoritative
inventory resource.

`CitizenServices`, physical parking-meter receipts, and CreatorLink item
rewards currently require the transactional `m-inventory` API.

### Item images

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
    Providers = {
        ["m-inventory"] = {
            BaseUrl = "http://localhost:12890/m-inventory/web/assets/items",
            Extension = ".png",
        },
    },
}
```

With `Provider = "auto"`, the renderer uses the m-inventory runtime marker when
available and otherwise uses `AutoFallback`. HELIX export proxies cannot
reliably prove package availability, so choose a provider explicitly for custom
setups.

The renderer tries `clothing/<itemId>.png`, then `<itemId>.png`, then
`FallbackUrl`. Absolute HTTP, data, and blob URLs supplied by an App are also
supported.

## Citizen Services

```lua
Config.CitizenServices = {
    MaxDistance = 500.0,
    Services = {
        state_id = {
            enabled = true,
            itemId = "state_id",
            feePence = 2500,
            validityDays = 1460,
            issuedBy = "Pacifica Department of State",
            numberPrefix = "PAC",
        },
    },
}
```

Each service controls availability, inventory item id, integer fee in pence,
validity period, issuer, and document-number prefix. Distance and eligibility
must be validated server-side. This feature depends on the configured Desktop,
inventory, and document providers.

## Camera and gallery

```lua
Config.Camera = {
    CaptureWidth = 720,
    CaptureHeight = 900,
    SelfieExposureBias = 0.8,
    RearExposureBias = 0.0,
    MaxPhotos = 200,
    ServerRequestTimeoutMs = 20000,
    Storage = {
        Mode = "custom",
        LocalDirectory = "MPhone/Photos/",
        Custom = {
            UploadTicketPath = "/api/mphone/photos/upload-ticket",
            DeletePath = "/api/mphone/photos/",
        },
        FiveManage = {
            Url = "https://api.fivemanage.com/api/v3/file",
            PresignedUrl = "https://api.fivemanage.com/api/v3/file/presigned-url",
        },
    },
}
```

- Capture settings control render dimensions and exposure bias.
- `MaxPhotos` limits retained player media.
- `ServerRequestTimeoutMs` bounds storage requests.
- `custom` is the production remote-storage path in the current public alpha.
- Other storage fields are compatibility or reserved values unless the
  installed build explicitly implements them.

Server-only endpoints and credentials belong in:

```text
PhoneApps/Camera/camera_storage_local.lua
```

Create it from `camera_storage_local.example.lua`. The local file is ignored by
Git and overrides safe tracked defaults. Never place a real key in `config.lua`
or the example file.

## App SDK

```lua
Config.SDK = {
    Enabled = true,
    Version = 1,
    RequestTimeoutMs = 10000,
    MaxPayloadDepth = 8,
    MaxPayloadKeys = 256,
    Apps = {},
}
```

Bundled module entry:

```lua
{
    Feature = "MyFeature", -- optional
    Manifest = "PhoneApps.MyApp.manifest",
    Server = "PhoneApps.MyApp.server",
}
```

External packages should call `RegisterApp` instead of editing this table.
`MaxPayloadDepth` and `MaxPayloadKeys` are reserved values and are not a
guaranteed enforcement boundary in `0.9.1-alpha`. Every provider must bound and
validate its own payload.

See [APP_DEVELOPMENT.md](APP_DEVELOPMENT.md) and
[CUSTOM_APPS.md](CUSTOM_APPS.md).

## Widget SDK

```lua
Config.WidgetSDK = {
    Enabled = true,
    Version = 1,
    Widgets = {
        {
            Feature = "Parking", -- optional
            Manifest = "PhoneWidgets.AppWidgets.parking_manifest",
            Client = "PhoneWidgets.AppWidgets.client",
            Server = "PhoneWidgets.AppWidgets.server",
        },
    },
}
```

`Manifest` is required for bundled modules. `Client` and `Server` are optional
module paths. External packages should call `RegisterWidget`.

See [CUSTOM_WIDGETS.md](CUSTOM_WIDGETS.md).

## Map and commerce profile

```lua
Config.ActiveMap = "TEST_MAP" -- TEST_MAP or PACIFICA_MAP
Config.ShopPricesIncludeVAT = false
Config.ShopVATRate = 0.20
Config.ShopProducts = {}
Config.ShopLocations = {}
Config.ATMs = {}
Config.CommerceMapProfiles = {}
```

- `ActiveMap` selects a coordinate/profile table.
- `TEST_MAP` is intentionally available for HELIX Studio development.
- A test map does not automatically authorize privileged mutations.
- Shop product `price` values are game dollars.
- `ShopPricesIncludeVAT` controls whether product prices already include VAT.
- `ShopVATRate` is a decimal rate (`0.20` is 20%).
- Shop locations define ids, labels, transforms, products, delivery points,
  interaction presentation, and ownership options.
- ATMs define id, label, deposit support, and decimal fee rate.
- `CommerceMapProfiles` selects the active Shop and ATM collections.

Desktop interactables and spatial presentation are owned by `m-desktop`; these
tables retain phone-hosted commerce domain configuration and compatibility
data.

## Developer operations

```lua
Debug = false

Config.Developer = {
    AllowTestMutations = false,
}
```

Privileged test payouts or debits require both `Debug = true` and
`AllowTestMutations = true`. Keep both disabled in production and public
Worlds.

## Units and money

The project uses different units at different boundaries:

- Banking and document service APIs use integer pence/cents.
- Parking App `pricePer15` uses integer pence/cents.
- Physical meter `PricePerStep` and Shop product `price` use game dollars and
  are converted by server code.
- Percentage values are whole percentages unless documented as decimal rates.

Never infer a unit from the WebUI display. Follow the field contract and keep
all authoritative calculations on the server.
