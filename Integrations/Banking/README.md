# Banking integration adapter

`server.lua` normalizes banking calls used by device Apps.

## Providers

- `Config.Use.Bank = "mbank"` or compatible aliases call `Config.Banking.Resource` (default `m-banking`).
- `Config.Use.Bank = "qb"` uses the current qb-core money/account compatibility path.

The adapter normalizes profiles, balances, credit/debit results, transfers, ATM operations, and debit notifications. It also installs temporary legacy database method aliases used by existing presentation modules.

This module has no cross-resource exports. External consumers should call [../../../m-banking/API.md](../../../m-banking/API.md) or their selected provider directly.

All amounts are normalized as integer pence at the device boundary.
