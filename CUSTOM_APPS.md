# m-phone Custom Apps SDK

Custom Apps run their own HTML, CSS, JavaScript, client Lua, and server Lua without modifying the compiled m-phone WebUI. The phone provides only a sandboxed frame and a controlled request bridge.

## Template package

Phone and Tablet reference Apps are distributed separately from the compiled
`m-phone` runtime. The template package demonstrates:

- an App manifest;
- a sandboxed WebUI entry point;
- arbitrary HTML, CSS, and JavaScript;
- requests from JavaScript to Lua;
- responses from server Lua back to the App.

The Tablet template is the separate wide-screen reference for Tablet. It
uses its own manifest, Lua handler and WebUI. Its manifest enables
only `surfaces.tablet`, while the Phone template explicitly disables Tablet.
This prevents Phone applications from silently appearing in the Tablet app
registry.

Tablet applications should use a Tablet-specific identifier and surface:

```lua
return {
    id = "mycompany.tabletapp",
    web = { entry = "TabletApps/MyTabletApp/web/index.html", mode = "sandboxed" },
    surfaces = { phone = false, desktop = false, tablet = true, pos = false },
    defaultInstalled = true,
}
```

The Tablet shell provides its own paged app grid, six-slot dock, drag/drop/swap
editing, widget layouts, language, volume and appearance preferences. These
preferences do not read or modify Phone layout state.

## Manifest

Register the same manifest on client and server:

```lua
local manifest = {
    id = "mycompany.myapp",
    sdkVersion = 1,
    version = "1.0.0",
    label = "My App",
    provider = "my-custom-apps",
    icon = "PhoneApps/MyApp/web/icon.svg",
    web = { entry = "PhoneApps/MyApp/web/index.html" },
    surfaces = { phone = true },
    defaultInstalled = true,
    serverExport = "HandleMPhoneRequest",
}

exports["m-phone"]:RegisterApp(manifest)
```

The provider must expose a matching server handler:

```lua
exports("my-custom-apps", "HandleMPhoneRequest", function(appId, controller, action, payload, context)
    if appId == "mycompany.myapp" and action == "ping" then
        return { ok = true, message = "Pong" }
    end
    return { ok = false, error = "unknown_action" }
end)
```

## Browser SDK

Load the SDK before the App script:

```html
<script src="/m-phone/web/sdk/m-phone-sdk.js"></script>
```

Then use the public API:

```js
MPhone.on('ready', (context) => console.log(context));
const result = await MPhone.request('ping', { message: 'Hello' });
MPhone.close();
```

## Security boundary

The App iframe uses `sandbox="allow-scripts allow-forms"` without `allow-same-origin`. Custom JavaScript cannot access the parent DOM or the internal `hEvent` bridge. It can only use messages accepted by the public SDK host.

## Recommended distribution

Keep production Apps in a separate package such as `m-phone-customapps`. This
prevents an `m-phone` update from replacing user-created Apps. Install the
separate template package and copy the reference matching the target surface.
