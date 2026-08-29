# Clock widget

The Clock widget is a built-in Phone widget using `PhoneWidgets/Clock/web/index.html`.

`manifest.lua` declares its identity and supported sizes. `client.lua` returns the current server time for `open` and `refresh`; the WebUI formats the visible clock.

Clock presentation is not an authoritative gameplay timer. Systems with expiry or cooldown rules must use their server timestamps.
