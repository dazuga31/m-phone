# Developing Apps for m-phone

`m-phone` supports separately packaged Phone and Tablet Apps without requiring
changes to the compiled core WebUI. An App owns its HTML, CSS, JavaScript, Lua
bridge, and authoritative server validation.

## Start from a template

The runtime repository includes copy-ready examples:

- `PhoneApps/TemplateApp`
- `TabletApps/TemplateApp`

Standalone React/TypeScript template projects may be distributed separately.
Do not edit the minified files under `web/assets` to add an App.

## Recommended package layout

```text
my-phone-app/
|-- package.json
|-- manifest.lua
|-- client.lua
|-- server.lua
`-- web/
    |-- index.html
    |-- app.js
    |-- style.css
    `-- icon.svg
```

Use a globally unique lowercase App id such as `mycompany.dispatch`. Keep
gameplay persistence and business rules in the resource that owns that domain.
The device App should remain a presentation adapter.

## Manifest

Register the same manifest on the client and server:

```lua
local manifest = {
    id = "mycompany.dispatch",
    sdkVersion = 1,
    version = "1.0.0",
    label = "Dispatch",
    description = "Live service requests.",
    developer = "My Company",
    provider = "my-dispatch",
    icon = "web/icon.svg",
    web = {
        entry = "web/index.html",
        mode = "sandboxed",
    },
    surfaces = {
        phone = true,
        tablet = false,
        desktop = false,
        pos = false,
    },
    installable = true,
    defaultInstalled = false,
    category = "services",
    permissions = {
        "player.basic",
        "notifications",
    },
    serverExport = "HandleMPhoneRequest",
}

exports["m-phone"]:RegisterApp(manifest)
```

Phone and Tablet use the same registry, but content is separated by the
`surfaces` flags. A Phone App does not automatically appear on Tablet.

For bundled modules loaded by `m-phone`, add the module to `Config.SDK.Apps`:

```lua
Config.SDK.Apps = {
    {
        Feature = "MyFeature", -- optional Config.Features key
        Manifest = "PhoneApps.MyApp.manifest",
        Server = "PhoneApps.MyApp.server",
    },
}
```

External resources should register themselves through the public exports
instead of editing `config.lua`.

## Browser bridge

Load the public SDK before the App script:

```html
<script src="/m-phone/web/sdk/m-phone-sdk.js"></script>
<script src="./app.js"></script>
```

```js
MPhone.on('ready', (context) => {
  console.log(context.language, context.surface)
})

const response = await MPhone.request('list', { page: 1 })
MPhone.close()
```

Requests are correlated and time out according to
`Config.SDK.RequestTimeoutMs`.

## Server handler

The provider resource exposes the export named by `serverExport`:

```lua
exports("my-dispatch", "HandleMPhoneRequest", function(
    appId,
    controller,
    action,
    payload,
    context
)
    if appId ~= "mycompany.dispatch" then
        return { ok = false, error = "invalid_app" }
    end

    if action == "list" then
        return {
            ok = true,
            requests = {},
        }
    end

    return { ok = false, error = "unknown_action" }
end)
```

Treat `payload`, App identity, player identity, prices, ownership, and roles as
untrusted. Resolve the player from `controller` and validate every mutation on
the server.

## Local files and URLs

- Keep all App paths relative to the provider resource.
- Use a dedicated icon owned or licensed by the App author.
- Do not reference source-only Vite paths in the runtime manifest.
- Do not rely on parent DOM access. The iframe is sandboxed without
  `allow-same-origin`.

## Checklist

1. Choose a unique id and explicit surfaces.
2. Register the same manifest on client and server.
3. Implement a provider export for authoritative requests.
4. Add timeout, payload, ownership, and rate-limit validation.
5. Test installation, removal, language, theme, reopen, and unavailable-provider
   states.
6. Test the production build inside HELIX, not only in a browser mock.

See [CUSTOM_APPS.md](CUSTOM_APPS.md), [API.md](API.md),
[PERMISSIONS.md](PERMISSIONS.md), and [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
