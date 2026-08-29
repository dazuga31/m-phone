# Phone Apps

Phone Apps are implementations designed for the narrow Phone frame. Built-in Apps may be compiled into the shared renderer; SDK Apps use a local `manifest.lua`, optional client/server Lua, and a sandboxed `web/` entry.

Use [TemplateApp](TemplateApp/README.md) as the copy-ready SDK example. Complex gameplay must remain in its owning resource and be accessed through exports or validated events.

Current modules:

- [Bank](Bank/README.md)
- [Camera and Gallery](Camera/README.md)
- [Courier](Courier/README.md)
- [CreatorLink](CreatorLink/README.md)
- [Garage](Garage/README.md)
- [Parking](Parking/README.md)
- [TemplateApp](TemplateApp/README.md)

Their presence on the home screen is controlled by feature flags, installation state, and the App registry rather than directory discovery alone.
