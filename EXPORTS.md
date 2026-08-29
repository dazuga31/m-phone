# m-phone Exports and Public API Roadmap

This document is the source-of-truth audit for the Lua exports and browser APIs currently exposed by `m-phone`. It also defines the recommended public API additions for Phone and Tablet integrations.

Audit date: 2026-08-15  
Current SDK version: `1`  
Package status: pre-`1.0.0`; proposed APIs in this document are not callable until implemented.

## Status legend

| Status | Meaning |
| --- | --- |
| **Implemented** | Registered by the current Lua runtime and callable on the stated side. |
| **Internal** | Exists in the package, but is not a stable public integration contract. |
| **Restricted** | Implemented, but intended only for trusted server resources or administration. |
| **Proposed** | Recommended API design; it is not implemented yet. |
| **Provisional** | Implemented for an unfinished feature and may change before `1.0.0`. |

## Calling convention

HELIX exports are called through the package export proxy:

```lua
local result = exports["m-phone"]:BankGetBalance(controller)
```

Client exports are available only in client Lua. Server exports are available only in server Lua. `RegisterApp` and `RegisterWidget` intentionally exist on both sides, so an external package must register the same manifest in both runtimes.

Phone and Tablet do **not** use separate SDK registries. They share the App and Widget SDKs and are separated by manifest surface flags:

```lua
surfaces = {
    phone = true,
    tablet = false,
    desktop = false,
    pos = false,
}
```

An App or Widget is visible on Tablet only when `surfaces.tablet == true`. Phone content is not automatically copied to Tablet.

---

## Implemented core server exports

These exports are registered in `server.lua`.

### Documents

| Export | Signature | Current behavior |
| --- | --- | --- |
| `DocumentsGet` | `DocumentsGet(documentId)` | Returns the document row or `nil`. |
| `DocumentsGetActive` | `DocumentsGetActive(holderId, documentType)` | Returns the active document matching holder and type. |
| `DocumentsGetByRequestId` | `DocumentsGetByRequestId(requestId)` | Resolves an idempotent document request. |
| `DocumentsCreatePending` | `DocumentsCreatePending(document)` | Creates a pending document through the internal DB layer. |
| `DocumentsSetStatus` | `DocumentsSetStatus(documentId, status)` | Updates a document status through the internal DB layer. |
| `DocumentsCancel` | `DocumentsCancel(documentId, reason?)` | Cancels a pending document through the phone-owned compatibility layer. |

Status: **Implemented**, but currently a low-level service contract. The returned DB shapes and accepted status values are not normalized by the export layer, so these should be treated as internal integrations until formal document schemas are documented.

### Language

| Export | Signature | Returns |
| --- | --- | --- |
| `GetPlayerLanguage` | `GetPlayerLanguage(controller, fallback?)` | Stored language, or `fallback`, or `"en"`. |
| `SetPlayerLanguage` | `SetPlayerLanguage(controller, language)` | `true` on success, otherwise `false`. |

Status: **Implemented**.

### Identity and photos

| Export | Signature | Purpose |
| --- | --- | --- |
| `GetPlayerId` | `GetPlayerId(controller)` | Resolves the stable player identifier used by compatibility adapters. |
| `ListPlayerPhotos` | `ListPlayerPhotos(playerId, limit?)` | Lists photos owned by a player. |
| `GetPlayerPhoto` | `GetPlayerPhoto(playerId, photoId)` | Reads one player-owned photo. |

Status: **Internal**. These exports exist for trusted presentation adapters;
they are not a browser-facing media API.

### Banking

These `m-phone` exports are compatibility wrappers over the provider selected
by `Config.Use.Bank`. The `qb` provider reads and writes live qb-core money;
the `mbank` provider delegates to the authoritative `m-banking` resource.
New full-stack banking integrations should call `m-banking` directly, while
device Apps may use these stable wrappers.

All bank amounts are integer pence. For example, `$12.50` is `1250`.

| Export | Signature | Purpose |
| --- | --- | --- |
| `BankGetBalance` | `BankGetBalance(controller)` | Reads the player's live bank balance. |
| `BankDebit` | `BankDebit(controller, amountPence, reference?, extra?)` | Debits an external purchase. |
| `BankCredit` | `BankCredit(controller, amountPence, reference?, extra?)` | Credits a player account. |
| `BankClear` | `BankClear(controller, reference?, extra?)` | Debits the complete account balance. |

Restricted Desktop compatibility operations are also implemented:

| Export | Purpose |
| --- | --- |
| `BankProvider` | Returns the active provider descriptor. |
| `BankGetAccountByPlayerId` | Reads an account for a trusted player id. |
| `BankCreditByPlayerId` | Credits a trusted player id. |
| `BankDebitByPlayerId` | Debits a trusted player id. |
| `BankGetAtmProfile` | Builds the ATM presentation profile. |
| `BankTransactAtm` | Performs a validated ATM transaction. |
| `BankNotifyPlayerDebit` | Sends a debit notification to the affected player. |

These operations are **Restricted** and currently support `m-desktop` while
the compiled browser remains hosted by `m-phone`. New gameplay resources must
call `m-banking` directly.

Common balance result:

```lua
{
    ok = true,
    balancePence = 125000,
}
```

Common failures include:

```lua
{ ok = false, error = "player_not_found", balancePence = 0 }
{ ok = false, error = "no_bank_account", balancePence = 0 }
```

The `qb` provider has no persistent ledger in base qb-core, so history and
recent-recipient queries return empty arrays. Recipient transfers require the
target player to be online. Use `mbank` when those capabilities are required.

`BankDebit`, `BankCredit`, and especially `BankClear` must be called only from trusted server resources. `BankClear` should be classified as **Restricted** and omitted from normal third-party integration examples.

Example:

```lua
local bank = exports["m-phone"]:BankGetBalance(controller)
if not bank.ok then
    return bank
end

local charge = exports["m-phone"]:BankDebit(
    controller,
    1500,
    "Parking zone 0001",
    { zoneId = "0001", minutes = 15 }
)
```

### Trucker

Authoritative Trucker contracts, progression, rewards, invoices, vehicle
lifecycle and the full Trucker DesktopApp contract live in `m-trucker`.
`m-phone` retains only lightweight read-only Phone/Tablet views for active
routes, invoices, history and driver status. The compiled shared renderer stays
in `m-phone` temporarily, while the Desktop shell and spatial lifecycle move to
`m-desktop`.

Stable `m-trucker` server exports:

- `IsReady()`
- `EnsureProfileForPlayer(playerId)`
- `GetOrdersForPlayer(playerId, limit?, depotId?)`
- `GetProfileForPlayer(playerId)`
- `GetActiveRouteForPlayer(playerId)`
- `CreateSupplyOrder(data)`
- `DeleteSupplyOrder(orderId)`

Existing `m-phone:trucker:*` events are preserved as the UI compatibility
contract. New gameplay resources must use `m-trucker` exports instead of
depending on `_G.MPhone` or Trucker globals.

### Courier

Authoritative Courier jobs, assignment, progression and invoice orchestration
live in `m-courier`. `m-phone` retains the Courier App client and the existing
`m-phone:courier:*` compatibility events.

Stable `m-courier` server exports:

- `IsReady()`
- `GetData(controller)`
- `GetDataForPlayer(playerId)`
- `EnsureProfileForPlayer(playerId)`
- `GetProfileForPlayer(playerId)`
- `GetActiveJobForPlayer(playerId)`
- `GetOpenJobs(limit?)`
- `AcceptJob(controller, data)`
- `CompleteJob(controller, data)`
- `CancelJob(controller, data)`
- `PrintInvoice(controller, data)`

New gameplay integrations must use these exports instead of `DB.Courier`,
Courier SQLite tables or qb-core directly.

### Business

Authoritative Shop Manager, Kiosk checkout, business balances, supply orders
and Furniture provider orchestration live in `m-business`. `m-phone` retains
only their Desktop/POS presentation and compatibility events.

Stable `m-business` server exports are documented in
`Scripts/m-business/API.md`. New integrations must call that resource instead
of `DB.Shops` or `_G.MPhone.Business`.

### Jobs

Job Centre applications, cooldowns and authoritative character snapshots now
live in `m-jobs`. `m-phone` retains the Job Centre client and these compatibility
events:

- `m-phone:jobcentre:getApplicationProfile`
- `m-phone:jobcentre:submitApplication`

Stable `m-jobs` server exports:

- `IsReady()`
- `GetPlayerId(controller)`
- `GetApplicationProfile(controller)`
- `SubmitApplication(controller, payload)`
- `GetLatestApplicationByPlayer(playerId)`

Future organization review, clock-on and dispatch APIs should extend
`m-jobs`; they must not be implemented inside a Phone, Tablet or Desktop App.

---

## Implemented App SDK exports

### Client and server

| Export | Side | Signature | Returns |
| --- | --- | --- | --- |
| `RegisterApp` | Client + Server | `RegisterApp(manifest)` | `true, appId` or `false, errorCode`. |
| `GetRegisteredApps` | Client + Server | `GetRegisteredApps()` | Array of public App manifests. |

Register the same manifest on both sides:

```lua
local manifest = {
    id = "mycompany.dispatch",
    sdkVersion = 1,
    version = "1.0.0",
    label = "Dispatch",
    description = "Dispatch board",
    developer = "My Company",
    provider = "my-dispatch",
    icon = "web/icon.png",
    web = { entry = "web/index.html" },
    surfaces = {
        phone = true,
        tablet = true,
        desktop = false,
        pos = false,
    },
    installable = true,
    defaultInstalled = false,
    category = "services",
    permissions = { "notifications" },
    order = 500,
    serverExport = "HandleMPhoneRequest",
}

local ok, result = exports["m-phone"]:RegisterApp(manifest)
```

The external provider must expose the configured server handler:

```lua
exports("my-dispatch", "HandleMPhoneRequest", function(
    appId,
    controller,
    action,
    payload,
    context
)
    if action == "getState" then
        return { ok = true, jobs = {} }
    end

    return { ok = false, error = "unknown_action" }
end)
```

Provider handler signature:

```text
HandleMPhoneRequest(appId, controller, action, payload, context)
```

The current context contains at least:

```lua
{
    surface = "phone", -- phone, tablet, desktop, or pos
    language = "en",
}
```

### Normalized App manifest fields

| Field | Notes |
| --- | --- |
| `id` | Required; normalized to lowercase and limited to `a-z`, `0-9`, `.`, `_`, `-`. |
| `sdkVersion` | Defaults to `1`; must not exceed the configured SDK version. |
| `version` | App version string. |
| `label`, `description`, `developer` | Public App metadata. |
| `provider` | Required HELIX package name. |
| `icon` | Optional provider-relative icon path. |
| `web.entry` | Required provider-relative HTML entry; traversal paths are rejected. |
| `surfaces` | Phone defaults to enabled; Tablet, Desktop, and POS require explicit opt-in. |
| `installable` | Defaults to `true`. |
| `defaultInstalled` | Defaults to `false`. |
| `category` | Defaults to `other`. |
| `permissions` | Declared capability names; see security limitations below. |
| `order` | Display order; defaults to `900`. |
| `serverExport` | Defaults to `HandleMPhoneRequest`. |

Generated WebUI URL:

```text
http://localhost:12890/<provider>/<web.entry>
```

---

## Implemented Widget SDK exports

### Client

| Export | Signature | Returns |
| --- | --- | --- |
| `RegisterWidget` | `RegisterWidget(manifest)` | `true, widgetId` or `false, errorCode`. |
| `RegisterWidgetClientHandler` | `RegisterWidgetClientHandler(widgetId, handler)` | `true, widgetId` or `false, errorCode`. |
| `GetRegisteredWidgets` | `GetRegisteredWidgets()` | Sorted array of public Widget manifests. |

Client handler signature:

```lua
exports["m-phone"]:RegisterWidgetClientHandler(widgetId, function(
    action,
    payload,
    context,
    done
)
    if action == "refresh" then
        return { ok = true, value = "Local state" }
    end

    return { forwardToServer = true }
end)
```

The handler may:

- return a result synchronously;
- call `done(result)` asynchronously;
- return `{ forwardToServer = true }` to use the server provider.

### Server

| Export | Signature | Returns |
| --- | --- | --- |
| `RegisterWidget` | `RegisterWidget(manifest)` | `true, widgetId` or `false, errorCode`. |

There is currently no server-side `GetRegisteredWidgets` export and no public server handler registration export. Built-in handlers are loaded only through `Config.WidgetSDK.Widgets`; external providers use `manifest.serverExport`.

Provider handler signature:

```text
HandleMPhoneWidgetRequest(widgetId, controller, action, payload, context)
```

### Canonical Widget sizes

The canonical sizes are:

- `minimal`
- `medium`
- `wide`

Legacy `small` and `large` values are accepted and normalized to `minimal` and `wide`.

Widget manifests may independently opt into Phone, Tablet, and Desktop surfaces. Phone defaults to enabled; other surfaces require explicit opt-in.

---

## Implemented browser APIs

Custom App and Widget WebUIs run in sandboxed iframes. They cannot access the parent DOM or HELIX `hEvent` directly.

### App browser SDK

Load:

```html
<script src="/m-phone/web/sdk/m-phone-sdk.js"></script>
```

API:

| Method | Purpose |
| --- | --- |
| `MPhone.getContext()` | Returns the last initialization context. |
| `MPhone.request(action, payload?)` | Sends a request to the App's Lua provider and returns a Promise. |
| `MPhone.close()` | Requests that the host close the App. |
| `MPhone.on(name, handler)` | Subscribes to SDK events such as `ready` and `response`. |
| `MPhone.off(name, handler)` | Removes an SDK event handler. |

Initialization context:

```js
{
  appId: 'mycompany.dispatch',
  surface: 'phone',
  language: 'en',
  permissions: ['notifications'],
  theme: 'dark'
}
```

Requests time out after 10 seconds in the current browser SDK.

### Widget browser SDK

Load:

```html
<script src="/m-phone/web/sdk/m-phone-widget-sdk.js"></script>
```

API:

| Method | Purpose |
| --- | --- |
| `MPhoneWidget.getContext()` | Returns the current Widget context. |
| `MPhoneWidget.request(action, payload?)` | Sends a Widget request and returns a Promise. |
| `MPhoneWidget.on(name, handler)` | Subscribes to `ready` or `response`. |
| `MPhoneWidget.off(name, handler)` | Removes an event handler. |

Widget context includes `widgetId`, canonical `size`, `language`, `surface`, `permissions`, and `theme`.

---

## CreatorLink feature exports

CreatorLink is an optional m-phone feature, not part of the generic device SDK. Its exports should stay namespaced and be called only by trusted server resources.

| Export | Status | Purpose |
| --- | --- | --- |
| `HandleCreatorLinkRequest` | Internal | Built-in App SDK provider handler. |
| `HandleCreatorLinkWidgetRequest` | Internal | Built-in Widget SDK provider handler. |
| `GetCreatorLinkPlayerBenefits` | Implemented | Reads active support link and benefits. |
| `GetCreatorLinkActiveEntitlement` | Implemented | Reads one active entitlement type. |
| `ReviewCreatorLinkBenefitRequest` | Restricted | Performs staff benefit-request transitions. |
| `GetCreatorLinkPartnerBenefitRequests` | Restricted | Lists a partner's benefit requests. |
| `GetCreatorLinkPartnerApplications` | Restricted | Lists partner applications by status. |
| `ReviewCreatorLinkPartnerApplication` | Restricted | Performs staff application review transitions. |
| `RecordCreatorLinkTransaction` | Provisional | Records a LIX transaction and calculated commission. |
| `SettleCreatorLinkTransaction` | Provisional | Settles a pending transaction. |
| `ReverseCreatorLinkTransaction` | Provisional | Reverses a transaction. |

The authoritative LIX purchase API is not available yet. `RecordCreatorLinkTransaction` must not be treated as proof of a real purchase until it is connected to the authoritative HELIX transaction source.

---

## Internal APIs that are not public exports

`client.lua` currently exposes `_G.MPhoneClient` for modules inside `m-phone`. It contains helpers including:

- `SetVisible`
- `OpenFrame`
- `CloseUI`
- `TogglePhone`
- `ToggleTablet`
- `TogglePos`
- `ToggleDesktop`
- `ActivateSpatialDesktop`
- `IsOpen`
- `NotifyPhone`
- `PushChatSystemMessage`

External packages must not depend on `_G.MPhoneClient`. It is a private implementation object and may change without compatibility guarantees.

`m-desktop` currently consumes a narrow, internal host bridge while the shared
compiled browser remains in `m-phone`:

- `RegisterClientUIHandler`
- `SendClientUIEvent`
- `GetDesktopRuntimeConfig`
- `OpenClientFrame`
- `CloseClientUI`
- `ToggleClientFrame`
- `PushClientInitialData`
- `DesktopAttachSpatialUI`
- `DesktopDetachSpatialUI`
- `DesktopSetNativeSpatialState`

The older `DesktopOpenFrame`, `DesktopTogglePos`, `DesktopToggle` and
`DesktopPushInitialData` names are compatibility aliases. These exports are
**Internal**, not general Phone SDK operations.

The following are also internal transport details, not public APIs:

- `m-phone:sdk:request`
- `m-phone:sdk:response`
- `m-phone:widgetSdk:request`
- `m-phone:widgetSdk:response`
- raw WebUI events such as `openPhone`, `openTablet`, `openDesktop`, and `openPos`

Public integrations should use exports so validation, permissions, compatibility, and logging can be centralized.

---

## Audit findings and current gaps

1. **No public device lifecycle API.** External resources cannot safely open Phone or Tablet, open a specific App, close a surface, or query the active surface through stable exports.
2. **No public notification API.** Notification and system-message helpers exist only on `_G.MPhoneClient`.
3. **App SDK has no client handler API.** Widgets can register a local Lua handler, but Apps always forward requests to the server.
4. **No unregister lifecycle.** App and Widget IDs remain in their runtime registries until resource restart.
5. **Duplicate IDs overwrite silently.** Registration currently replaces an existing manifest with the same ID.
6. **Widget server parity is incomplete.** It lacks `GetRegisteredWidgets`, explicit handler registration, and the same enabled/version checks used by the client.
7. **Permissions are declarations, not a complete security gate.** They reach the iframe context, but no centralized permission enforcement was found in the reviewed SDK dispatch path.
8. **Configured payload limits need enforcement.** `MaxPayloadDepth` and `MaxPayloadKeys` exist in config, but the reviewed App SDK bridge does not apply them before provider dispatch.
9. **Return contracts are inconsistent.** Some exports return booleans, some DB rows, and some `{ ok, error }` envelopes.
10. **Install/layout state has no public service API.** Contributors cannot safely install Apps, set badges, refresh Widgets, or read device preferences.
11. **Phone and Tablet are correctly separated at the surface layer**, but external code has no public API to target and navigate either surface.

---

## Recommended public exports

Everything in this section is **Proposed**.

### P0: device lifecycle

#### Client

```lua
OpenPhone(options?) -> result
OpenTablet(options?) -> result
OpenApp(appId, options?) -> result
CloseDevice(reason?) -> result
IsDeviceOpen() -> boolean
GetDeviceState() -> state
```

Recommended `OpenApp` options:

```lua
{
    surface = "phone", -- phone or tablet
    route = "conversation",
    params = { chatId = "chat_123" },
    focus = true,
}
```

Recommended state:

```lua
{
    ok = true,
    open = true,
    surface = "phone",
    activeAppId = "chat",
    inputCaptured = true,
}
```

### P0: notifications and badges

#### Client

```lua
Notify(payload) -> result
SetAppBadge(appId, count) -> result
ClearAppBadge(appId) -> result
```

#### Server

```lua
NotifyPlayer(controller, payload) -> result
PushSystemMessage(controller, payload) -> result
```

Recommended notification payload:

```lua
{
    id = "parking:0001:warning",
    surface = "phone", -- phone, tablet, or all
    appId = "parking",
    title = "Parking expires soon",
    text = "Zone 0001 has 10 minutes remaining.",
    icon = "parking",
    priority = "high", -- low, normal, high, critical
    ttlMs = 8000,
    data = { zoneId = "0001" },
    actions = {
        { id = "open", label = "Open" },
    },
}
```

### P0: SDK lifecycle parity

#### Client and server

```lua
UnregisterApp(appId) -> result
UnregisterWidget(widgetId) -> result
GetRegisteredApps(surface?) -> manifests
GetRegisteredWidgets(surface?) -> manifests
```

#### Client

```lua
RegisterAppClientHandler(appId, handler) -> result
RegisterAppLifecycleHandler(appId, handler) -> result
RefreshWidget(widgetId, payload?) -> result
```

Suggested App lifecycle callback names:

- `open`
- `focus`
- `blur`
- `background`
- `resume`
- `close`
- `languageChanged`
- `themeChanged`

### P1: installation and preferences

#### Server

```lua
HasAppInstalled(controller, appId, surface?) -> result
InstallApp(controller, appId, surface?) -> result
UninstallApp(controller, appId, surface?) -> result
GetPlayerDeviceSettings(controller, surface?) -> result
SetPlayerDeviceSettings(controller, surface, patch) -> result
```

#### Client

```lua
GetLocalDeviceSettings(surface?) -> result
GetTheme(surface?) -> result
GetLanguage() -> string
```

Phone and Tablet layout state must remain independent even when an App supports both surfaces.

### P1: communications

#### Server

```lua
GetPlayerPhoneNumber(controller) -> result
ResolvePhoneNumber(phoneNumber) -> result
SendSMS(controller, targetNumber, message, attachments?) -> result
PushConversationMessage(controller, conversationId, message) -> result
StartCall(controller, targetNumber, options?) -> result
EndCall(controller, callId, reason?) -> result
```

These exports should use the existing core and voice adapters rather than exposing qb-core or voice-provider details to Apps.

### P1: navigation and media

#### Client

```lua
SetWaypoint(location, options?) -> result
OpenMap(options?) -> result
OpenCamera(options?) -> result
OpenGallery(options?) -> result
GetGallerySelection(requestId?) -> result
```

Sensitive actions such as camera access should require manifest permissions and explicit user interaction.

### P2: service adapters

Banking and documents already have exports, but their long-term contract should be moved behind explicit adapter interfaces:

```lua
GetBankProvider() -> providerInfo
GetDocumentProvider() -> providerInfo
GetInventoryProvider() -> providerInfo
```

This keeps Phone and Tablet Apps independent from qb-core, `m-inventory`, and `m-documents` implementation details.

---

## Recommended return contract

New exports should always return a table:

```lua
{ ok = true, data = result }
```

or:

```lua
{
    ok = false,
    error = "stable_machine_code",
    message = "Optional developer-facing message",
}
```

Rules:

- never return raw database errors to clients;
- use stable lowercase error codes;
- validate controllers and ownership on the server;
- use integer pence for dollar balances;
- use integer LIX units for LIX transactions;
- support idempotency keys for purchases, documents, rewards, and message sends;
- avoid relying on Lua table iteration order in registry responses.

---

## Permissions and security requirements

Before the proposed API becomes public:

1. Enforce manifest permissions in the Lua dispatch layer, not only in WebUI.
2. Validate that the requesting App owns the requested capability.
3. Apply payload depth, key-count, string-length, and rate limits.
4. Reject duplicate App or Widget IDs unless the same provider performs an explicit update.
5. Remove registrations when the provider resource stops.
6. Keep banking, document creation, installation, and CreatorLink review operations server-authoritative.
7. Require trusted-resource allowlists for administration exports.
8. Log sensitive operations with package, App/Widget ID, player ID, request ID, and result code.
9. Keep raw HELIX controller objects and database rows out of browser payloads.

---

## Compatibility policy recommendation

- Keep SDK version `1` for the current manifest and browser request protocol.
- Add new exports without breaking existing App and Widget manifests.
- Introduce SDK version `2` only when changing request or manifest semantics.
- Return `sdk_version_unsupported` when a package requests a newer incompatible SDK.
- Mark deprecated exports in this file for at least one release before removal.
- Treat `_G.MPhoneClient` and raw `m-phone:*` events as unstable forever.
- Classify `BankClear` as administration-only before public release.

---

## Recommended implementation order

### Phase 1: stable integration foundation

1. Add client `OpenPhone`, `OpenTablet`, `OpenApp`, `CloseDevice`, and `GetDeviceState`.
2. Add client/server notification and badge exports.
3. Add App/Widget unregister and registry parity.
4. Add duplicate-provider validation and standardized results.
5. Enforce SDK payload limits and permissions.

### Phase 2: contributor quality of life

1. Add App client handlers and lifecycle callbacks.
2. Add Widget refresh/push data.
3. Add install/uninstall and settings services.
4. Add Phone/Tablet examples to the separately distributed template packages.

### Phase 3: gameplay integrations

1. Add communications exports.
2. Add navigation and waypoint exports.
3. Add camera/gallery permissioned exports.
4. Formalize bank, document, and inventory adapters.

---

## Documentation split for release

This audit should later be split into focused public pages:

- `EXPORTS.md` - callable Lua APIs and stability status;
- `EVENTS.md` - public lifecycle events only;
- `CUSTOM_APPS.md` - App manifest, Lua provider, and browser SDK tutorial;
- `CUSTOM_WIDGETS.md` - Widget sizes, handlers, and browser SDK tutorial;
- `PERMISSIONS.md` - capability declarations and enforcement rules;
- `MIGRATION.md` - deprecations and SDK-version changes.

Until those contracts are implemented, only entries marked **Implemented** in this document should be treated as callable.
