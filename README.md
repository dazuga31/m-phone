# m-phone

`m-phone` is an install-ready HELIX communication and device resource with Phone, Tablet, camera, gallery, communication, service Apps, and a compiled production WebUI.

This repository ships the compiled WebUI. React/TypeScript source and App/Widget template projects are distributed separately. Server owners configure integrations through Lua and do not need a JavaScript toolchain.

The clean-QB profile starts with Settings, App Store, Chat, Contacts, Calls,
Camera, Gallery, Bank, and Parking. Additional built-in and external Apps can
be exposed through the App Store and server configuration.

## Quick start

1. Download or clone this repository as `m-phone` inside the World scripts directory.
2. Install and start every package listed in `DEPENDENCIES.md`.
3. Review `config.lua`.
4. Configure camera storage only when Camera uploads are enabled.
5. Start `m-phone` after its required dependencies.
6. Use `Config.ActiveMap = "TEST_MAP"` for HELIX Studio testing.

## Documentation

- `INSTALLATION.md` - installation and first-run checks.
- `CONFIGURATION.md` - feature switches, map profile, and item images.
- `DEPENDENCIES.md` - required and optional integrations.
- `CUSTOM_APPS.md` - external Phone and Tablet App SDK.
- `CUSTOM_WIDGETS.md` - external Phone and Tablet Widget SDK.
- `API.md` - conventional public API entrypoint.
- `EXPORTS.md` - implemented Lua/browser APIs and the proposed public API roadmap.
- `COMPONENTS.md` - directory ownership and extraction boundaries.
- `SECURITY.md` - credential handling and vulnerability reporting guidance.
- `CHANGELOG.md` - public runtime release history.

## Current status

This package is in alpha. APIs and payload contracts may change before `1.0.0`.

## License

The Lua runtime and compiled `m-phone` distribution are released under the
[MIT License](LICENSE). Third-party trademarks, game assets, fonts, and media
remain subject to their respective owners and licenses.
