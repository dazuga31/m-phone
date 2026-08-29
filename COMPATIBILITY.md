# m-phone Compatibility

## Supported architecture

| Area | Current alpha support |
| --- | --- |
| Core | `qb-core`; `m-core` value is reserved |
| Banking | built-in `qb` adapter or `m-banking` through `mbank` |
| Inventory images | `m-inventory`, `qb-inventory`, custom base URL, reserved `hl-inventory` slot |
| Device UI | compiled Phone and Tablet WebUI |
| External Apps | App SDK version 1 |
| External Widgets | Widget SDK version 1 |
| Desktop | compatibility host bridge for the separate `m-desktop` resource |

Optional gameplay features require the provider resources listed in
[DEPENDENCIES.md](DEPENDENCIES.md).

## HELIX builds

The package uses HELIX Lua, WebUI, database, input, and player-controller APIs.
An exact HELIX build is not pinned in this alpha. Studio, standalone client, and
dedicated server can differ, so validate the complete flow on the target build.

When reporting a compatibility issue, include both the HELIX build and whether
the same operation succeeds in Studio.

## WebUI source boundary

The production bundle is included under `web/`. The main React/TypeScript
source and its dependency lockfile are not part of this repository. Node.js is
not required to install the runtime package.

Copy-ready Lua/HTML/JavaScript SDK examples are included, while standalone
source template projects may be published separately.

## Stability

This project is pre-`1.0.0`. Export signatures, manifest fields, internal
events, database columns, and compiled browser contracts can change between
alpha releases. Stable versus provisional operations are marked in
[EXPORTS.md](EXPORTS.md).
