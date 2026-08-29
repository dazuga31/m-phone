# m-phone Events

## Public integration policy

The stable public integration surface is the export API documented in
[API.md](API.md) and [EXPORTS.md](EXPORTS.md). Raw Lua event names are not a
stable cross-resource contract in `0.9.x-alpha`.

The runtime currently uses internal event namespaces for:

- App and Widget SDK requests;
- chat, contacts, SMS, and calls;
- camera and gallery operations;
- parking and parking-meter operations;
- settings and device state;
- compatibility bridges for extracted domain resources.

These names may change before `1.0.0`. External resources must not trigger an
internal `m-phone:*` event unless that event is explicitly documented as public
in a future release.

## Browser events

Sandboxed Apps and Widgets receive lifecycle and response messages through the
browser SDK:

- `MPhone.on('ready', handler)`
- `MPhone.request(action, payload)`
- `MPhone.close()`
- `MPhoneWidget.on('ready', handler)`
- `MPhoneWidget.request(action, payload)`

The exact browser contracts are documented in [CUSTOM_APPS.md](CUSTOM_APPS.md)
and [CUSTOM_WIDGETS.md](CUSTOM_WIDGETS.md).

## HELIX lifecycle

`m-phone` consumes HELIX lifecycle signals such as `HEvent:PlayerReady` to
initialize player-facing state. That is an engine dependency, not an event
emitted or owned by `m-phone`.

## Future public events

Public lifecycle events for device open, close, App focus, notifications, and
installation are planned but are not implemented as stable contracts in this
release. Do not build an integration around a proposed event listed in
`EXPORTS.md` until its status changes to **Implemented**.

## Security

An event reaching server Lua is never proof that its sender is authorized.
Resolve the player from the controller, validate the action, and apply
server-side rate limits. See [PERMISSIONS.md](PERMISSIONS.md).
