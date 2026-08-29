# m-phone Widget SDK

The Widget SDK registers sandboxed Phone/Tablet widgets with device-specific surfaces and responsive sizes.

## Public exports

- `RegisterWidget(manifest)` - client and server.
- `RegisterWidgetClientHandler(widgetId, handler)` - client-only local-data handler.
- `GetRegisteredWidgets()` - client-only public registry.

## Manifest contract

Required fields are `id`, `provider`, and `web.entry`. Supported sizes are:

- `minimal`
- `medium`
- `wide`

Legacy `small` and `large` values normalize to `minimal` and `wide`. Supported surfaces are `phone`, `tablet`, and `desktop`.

The host supplies `size`, `surface`, language, and request context. A widget must deliberately design each declared size rather than scaling one fixed layout.

## Handler rules

- Use a client handler for local presentation data that does not require authority.
- Return `{ forwardToServer = true }` or omit a client handler for trusted server data.
- Validate gameplay-affecting actions in the configured server export.
- Keep responses compact; widgets refresh more frequently than full Apps.

Start with [../PhoneWidgets/TemplateWidget/README.md](../PhoneWidgets/TemplateWidget/README.md) or [../TabletWidgets/TemplateWidget/README.md](../TabletWidgets/TemplateWidget/README.md).
