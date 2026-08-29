# m-phone dependencies

## Required packages

Start these packages before `m-phone`:

1. `qb-core`

`qb-core` provides the current player, cash, metadata, and the default `qb`
bank provider. Set `Config.Use.Bank = "mbank"` to delegate accounts and
transactions to `m-banking`. Other domain resources are optional and only
needed when their corresponding features are enabled.

Start `m-phone` after `qb-core` and after every optional provider required by an
enabled feature.

## Optional packages

Optional integrations are declared in `Config.Dependencies.Optional`. A missing optional package must not prevent the base Phone or unrelated Apps from loading.

| Package | Feature |
| --- | --- |
| `m-banking` | Full bank accounts, history, recipients, transfers, and ATM provider |
| `m-inventory` | Transactional document/reward items and item-image catalog |
| `qb-inventory` | Optional item-image catalog when selected by `Config.Inventory` |
| `hl-inventory` | Reserved custom inventory/image provider slot |
| `m-trucker` | Trucker contracts, progression, rewards, and vehicle lifecycle |
| `m-courier` | Courier jobs, assignments, progression, and invoices |
| `m-business` | Shop Manager, POS, supplies, and Furniture provider |
| `m-jobs` | Job Centre applications and cooldowns |
| `m-attachments` | Optional in-hand phone prop while the Phone is open |
| `m-desktop` | Desktop Apps, terminal validation, world presentation and spatial renderer lifecycle |
| `m-documents` | Citizen Services, parking receipts, and property document viewing |
| `m-markers` | Map and world marker integrations |
| `m-properties` | Property Market and property data |
| `m-vehicleshop` | Garage vehicle artwork and vehicle data |
| `hl-jungle` | Furniture Store integration |

Disable an unavailable integration in `Config.Features`. Startup diagnostics use
the `[m-phone][dependency]` prefix and report whether each optional integration
is enabled by configuration; they do not claim that a HELIX export proxy proves
the package is installed.

The base clean-QB profile requires only `qb-core`. The stock `qb` bank adapter
reads and writes live `money.bank`/`money.cash`; it intentionally exposes no
persistent transaction history and can transfer only to online recipients.
Select `mbank` for the complete banking feature set.

## Feature behavior

- Disabled Lua modules are not loaded.
- Disabled Desktop Apps are removed from terminal allowlists.
- Disabled Phone Apps are hidden from the Home screen and App Store.
- A stale request to open a disabled Phone App displays an unavailable state instead of mounting the App.
- Disabled device surfaces ignore their open/toggle requests.

## World package order

Install `qb-core`, then install only the optional resources required by enabled
features. When `Config.Use.Bank = "mbank"`, load `m-banking` before `m-phone`.
Load `m-phone` before `m-desktop` while the compiled browser and narrow UI host
bridge remain in `m-phone`; `m-desktop` retries until that bridge is ready.

The GitHub package does not install or update dependencies automatically.
