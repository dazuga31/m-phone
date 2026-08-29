# m-phone Permissions and Trust Model

## App and Widget declarations

App and Widget manifests may declare permission strings. Bundled examples
currently use values such as:

- `player.basic`
- `notifications`
- `world.weather`
- `creatorlink.profile`
- `creatorlink.partner`

These declarations describe intent and are passed to the sandbox context. In
`0.9.1-alpha`, they are not a complete central authorization system and must not
be treated as a security boundary.

## Server authority

Every provider handler must:

1. resolve the player from the HELIX controller;
2. verify App or Widget identity and the requested action;
3. validate ownership, role, balance, amount, target, and state;
4. enforce cooldowns and bounded payload sizes;
5. return only data required by the requesting surface;
6. log sensitive mutations without exposing secrets.

No browser permission grants money, items, ownership, administrator access, or
another player's data.

## Untrusted layers

Treat all of the following as untrusted:

- App and Widget JavaScript;
- WebUI messages;
- client Lua payloads;
- player ids, prices, metadata, and roles supplied by a client;
- paths and URLs supplied by third-party content.

Authoritative mutations belong in server Lua or the dedicated domain resource.

## Current payload limits

`Config.SDK.MaxPayloadDepth` and `Config.SDK.MaxPayloadKeys` are reserved
configuration values in this alpha. They are not currently a guaranteed
enforcement boundary. Provider handlers must still validate and bound their own
payloads.

Central permission enforcement may become stricter before `1.0.0`; that change
can be breaking for Apps that rely on undeclared access.
