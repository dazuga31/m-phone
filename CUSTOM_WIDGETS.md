# m-phone Custom Widgets SDK

Widgets are independent sandboxed HTML/CSS/JavaScript surfaces with optional client and server Lua. Contributors can add widgets without modifying or rebuilding the compiled m-phone React core.

## Bundled Phone widgets

- `PhoneWidgets/Clock` - local clock and date.
- `PhoneWidgets/Weather` - current HELIX world weather via `qb-weathersync`.
- `PhoneWidgets/AppWidgets` - first-party widgets for Phone Apps.

Phone and Tablet Widget templates are distributed separately. A Phone widget
must not silently appear on Tablet unless its manifest explicitly supports both
surfaces.

## Create a widget

1. Install the separate Widget template package and copy its Phone or Tablet reference.
2. Change the manifest `id`, `label`, `provider`, and WebUI entry.
3. Implement `client.lua` for local game data or `server.lua` for authoritative operations.
4. Add the module paths to `Config.WidgetSDK.Widgets`.

```lua
{
    Manifest = "PhoneWidgets.MyWidget.manifest",
    Client = "PhoneWidgets.MyWidget.client",
    Server = "PhoneWidgets.MyWidget.server",
}
```

Widgets distributed in another HELIX package can register themselves on client and server:

```lua
exports["m-phone"]:RegisterWidget(manifest)
```

An external client resource can also register a local request handler:

```lua
exports["m-phone"]:RegisterWidgetClientHandler(manifest.id, function(action, payload, context, done)
    if action == "refresh" then
        return { ok = true, value = "Client data" }
    end
    return { ok = false, error = "unknown_action" }
end)
```

Return `{ forwardToServer = true }` from the client handler when that action must be handled by `server.lua`.

Their provider package must expose the configured `serverExport` (defaults to `HandleMPhoneWidgetRequest`):

```lua
exports("my-widget-package", "HandleMPhoneWidgetRequest", function(widgetId, controller, action, payload, context)
    return { ok = true, value = "Hello from " .. widgetId }
end)
```

Canonical sizes are `minimal`, `medium`, and `wide`. Legacy `small` and `large` values are accepted and normalized to `minimal` and `wide`. Set `defaultEnabled = true` to place the widget on a new Home Screen automatically.

## Browser API

```html
<script src="/m-phone/web/sdk/m-phone-widget-sdk.js"></script>
```

```js
MPhoneWidget.on('ready', (context) => console.log(context.size, context.language));
const result = await MPhoneWidget.request('refresh', { value: 'HELIX' });
```

The iframe is sandboxed without `allow-same-origin`. Widgets cannot access the phone DOM or internal HELIX WebUI bridge directly.

## Home Screen controls

Use the settings button above the widget board to enter edit mode. Widgets can be added, removed, resized, and moved left or right. Layout is persisted locally per browser/WebUI storage.
