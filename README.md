# m-phone

[![Validation](https://github.com/dazuga31/m-phone/actions/workflows/validate.yml/badge.svg)](https://github.com/dazuga31/m-phone/actions/workflows/validate.yml)
[![Release](https://img.shields.io/github/v/release/dazuga31/m-phone?include_prereleases)](https://github.com/dazuga31/m-phone/releases)
[![License](https://img.shields.io/github/license/dazuga31/m-phone)](LICENSE)

`m-phone` is an install-ready HELIX communication and device resource with Phone, Tablet, camera, gallery, communication, service Apps, and a compiled production WebUI.

This repository ships the compiled WebUI. React/TypeScript source and App/Widget template projects are distributed separately. Server owners configure integrations through Lua and do not need a JavaScript toolchain.

The clean-QB profile starts with Settings, App Store, Chat, Contacts, Calls,
Camera, Gallery, Bank, and Parking. Additional built-in and external Apps can
be exposed through the App Store and server configuration.

## Quick start

1. Download or clone this repository as `m-phone` inside the World scripts directory.
2. Install `qb-core` and only the optional providers used by enabled features.
3. Review `config.lua`.
4. Configure camera storage only when Camera uploads are enabled.
5. Start `m-phone` after its required dependencies.
6. Use `Config.ActiveMap = "TEST_MAP"` for HELIX Studio testing.

## Documentation

### Installation and operation

- [Installation](INSTALLATION.md) - installation, camera setup, and first-run checks.
- [Configuration](CONFIGURATION.md) - complete public `config.lua` reference.
- [Dependencies](DEPENDENCIES.md) - required and optional integrations.
- [Controls](CONTROLS.md) - default Phone and parking-meter keys.
- [Database](DATABASE.md) - SQLite ownership, tables, backup, and recovery.
- [Migration](MIGRATION.md) - fresh installs, upgrades, and legacy extraction.
- [Troubleshooting](TROUBLESHOOTING.md) - common failures and bug-report checklist.
- [Compatibility](COMPATIBILITY.md) - supported providers, surfaces, and alpha limits.

### Development and API

- [API](API.md) - public API entrypoint.
- [Exports](EXPORTS.md) - implemented Lua/browser APIs and proposed roadmap.
- [App development](APP_DEVELOPMENT.md) - production App integration workflow.
- [Custom Apps](CUSTOM_APPS.md) - sandboxed Phone and Tablet App SDK.
- [Custom Widgets](CUSTOM_WIDGETS.md) - sandboxed Widget SDK.
- [Events](EVENTS.md) - public event policy and lifecycle boundaries.
- [Permissions](PERMISSIONS.md) - trust model and server validation.
- [Components](COMPONENTS.md) - directory ownership and extraction boundaries.
- [Contributing](CONTRIBUTING.md) - scope, checks, and pull-request guidance.

### Project policy

- [Security](SECURITY.md) - credentials and private vulnerability reporting.
- [Third-party notices](THIRD_PARTY_NOTICES.md) - licensing and asset boundaries.
- [Changelog](CHANGELOG.md) - public runtime release history.

## Current status

This package is in alpha. APIs and payload contracts may change before `1.0.0`.

## License

The Lua runtime and compiled `m-phone` distribution are released under the
[MIT License](LICENSE). Third-party trademarks, game assets, fonts, and media
remain subject to their respective owners and licenses. See
[Third-Party Notices](THIRD_PARTY_NOTICES.md).
