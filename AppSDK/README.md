# m-phone App SDK

The App SDK registers sandboxed HTML/JavaScript Apps from `m-phone` or another HELIX resource without exposing the compiled core WebUI source.

## Public exports

- `RegisterApp(manifest)` - client and server.
- `GetRegisteredApps()` - client and server.

Register the same manifest on both runtimes. The client owns rendering; the server owns trusted actions.

## Manifest fields

Required:

- `id` - lowercase stable identifier.
- `provider` - HELIX resource serving the web files.
- `web.entry` - provider-relative `index.html` path.

Common optional fields include `sdkVersion`, `version`, `label`, `description`, `developer`, `icon`, `surfaces`, `installable`, `defaultInstalled`, `category`, `permissions`, `order`, and `serverExport`.

Supported surfaces are `phone`, `tablet`, `desktop`, and `pos`. Enable only layouts the App actually supports.

## Request flow

1. The browser requests an SDK action.
2. Client Lua validates the registered App and forwards the request ID, action, payload, and context.
3. Server Lua invokes the provider's configured server export.
4. A structured response returns to the sandboxed App.

Validate permissions and gameplay data again on the server. Never trust App HTML, query strings, or browser payloads.

Start with [../PhoneApps/TemplateApp/README.md](../PhoneApps/TemplateApp/README.md) or [../TabletApps/TemplateApp/README.md](../TabletApps/TemplateApp/README.md).
