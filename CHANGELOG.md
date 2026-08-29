# Changelog

All notable public runtime changes will be documented in this file.

## [0.9.1-alpha] - 2026-08-29

- Added complete public configuration, controls, database, migration,
  troubleshooting, compatibility, permissions, events, and App-development
  documentation.
- Added contributor and third-party licensing guidance.
- Added private GitHub vulnerability-reporting instructions.
- Replaced workspace-only documentation links with standalone repository-safe
  references.
- Corrected required package ordering and expanded the root documentation index.
- Documented current alpha limitations without changing Lua or WebUI runtime
  behavior.

## [0.9.0-alpha] - 2026-08-29

- Prepared the install-ready GitHub distribution with compiled WebUI.
- Added selectable `qb`/`mbank` banking providers and a clean-QB safe profile.
- Preserved HELIX player-controller references for reliable clean-QB balance changes and online transfers.
- Added persistent QB metadata synchronization for generated phone numbers.
- Hardened HELIX export proxies and database row iteration for userdata-backed APIs.
- Prevented disabled optional integrations from loading or emitting missing-export errors.
- Added safe inventory image-provider resolution without trusting HELIX export proxies.
- Kept React/TypeScript WebUI source outside the runtime repository.
- Added safe local camera credential overrides and public configuration examples.
- Excluded runtime photos, databases, logs, archives, and local secrets from Git.
- Documented GitHub installation and current resource dependencies.
- Removed the stale production favicon request and verified the compiled WebUI asset graph.
- Disabled legacy Shop, Courier, and Trucker schema creation by default without deleting existing tables.
- Removed the disabled Courier feature configuration from unconditional package startup.
- Split Desktop-only Lua runtime and Desktop Apps into the separate `m-desktop` resource while preserving the compiled UI compatibility bridge.
- Added public MIT licensing and hardened camera-secret installation guidance.
