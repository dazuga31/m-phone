# Built-in App widgets

This folder contains manifests and a shared client handler for built-in Phone widgets:

- Activity
- Trucker
- Courier
- Gallery
- Chat
- Bank
- Parking

Every manifest declares `minimal`, `medium`, and `wide` support and uses the shared `PhoneWidgets/AppWidgets/web/index.html` renderer.

`client.lua` provides safe empty/default payloads when live domain data is unavailable. Live values should come from the owning App/provider through the Widget SDK; do not query gameplay databases from widget WebUI.

Each widget must remain useful at every declared size. If a new layout is not implemented, remove that size from its manifest rather than returning clipped content.
