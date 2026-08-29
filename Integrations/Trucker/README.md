# Trucker integration adapter

This adapter forwards lightweight Phone/Tablet reads and trusted supply-order integrations to `Config.Trucker.Resource` (default `m-trucker`).

Supported internal calls cover readiness, profile creation, order history, profile/status, active route, and supply-order create/delete operations. Legacy helper aliases remain while the compiled UI is migrated.

The full public domain contract is documented in `m-trucker/API.md` in the
separately distributed provider resource. This folder must not duplicate
Trucker persistence or gameplay validation.
