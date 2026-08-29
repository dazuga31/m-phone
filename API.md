# m-phone API

This file is the conventional API entrypoint for `m-phone`. The detailed status, signatures, trust levels, browser bridge, and proposed APIs live in [EXPORTS.md](EXPORTS.md).

For integration structure and security boundaries, also read
[APP_DEVELOPMENT.md](APP_DEVELOPMENT.md),
[EVENTS.md](EVENTS.md), and [PERMISSIONS.md](PERMISSIONS.md).

## App SDK

- `RegisterApp(manifest)` - client and server registration.
- `GetRegisteredApps()` - client and server public manifests.

## Widget SDK

- `RegisterWidget(manifest)` - client and server registration.
- `RegisterWidgetClientHandler(widgetId, handler)` - client data handler.
- `GetRegisteredWidgets()` - client public manifests.

See [CUSTOM_APPS.md](CUSTOM_APPS.md), [CUSTOM_WIDGETS.md](CUSTOM_WIDGETS.md), [AppSDK/README.md](AppSDK/README.md), and [WidgetSDK/README.md](WidgetSDK/README.md).

## Core server services

- Documents: `DocumentsGet`, `DocumentsGetActive`, `DocumentsGetByRequestId`, `DocumentsCreatePending`, `DocumentsSetStatus`, `DocumentsCancel`.
- Identity and media bridge: `GetPlayerId`, `ListPlayerPhotos`, `GetPlayerPhoto`.
- Language: `GetPlayerLanguage`, `SetPlayerLanguage`.
- Banking wrappers: `BankGetBalance`, `BankDebit`, `BankCredit`, `BankClear`.
- Restricted Desktop banking bridge: `BankProvider`, `BankGetAccountByPlayerId`, `BankCreditByPlayerId`, `BankDebitByPlayerId`, `BankGetAtmProfile`, `BankTransactAtm`, `BankNotifyPlayerDebit`.
- Notifications: `SendSystemMessage`.
- Desktop renderer bridge: `GetDesktopRuntimeConfig`.
- Transitional trucker bridge: `TruckerSupplyMarkDelivered`, `TruckerSupplyCancel`, `TruckerSupplySetStatus`.

Bank amounts are integer pence. Server mutation exports are trusted-resource APIs and must never be called directly from unvalidated WebUI payloads.

## Client UI and desktop bridge

- `RegisterClientUIHandler`
- `SendClientUIEvent`
- `GetDesktopRuntimeConfig`
- `FilterDesktopAllowedApps`
- `IsClientUIOpen`
- `OpenClientFrame`
- `CloseClientUI`
- `ToggleClientFrame`
- `PushClientInitialData`
- `DesktopOpenFrame`
- `DesktopTogglePos`
- `DesktopToggle`
- `DesktopPushInitialData`
- `DesktopAttachSpatialUI`
- `DesktopDetachSpatialUI`
- `DesktopSetNativeSpatialState`
- `DesktopActivateSpatial`
- `DesktopActivateNativeSpatial`
- `DesktopDeactivateSpatial`
- `DesktopRefreshMapMarkers`
- `UpdateTruckerRouteMarker`
- `SetTruckerVehicleMarker`

`GetDesktopRuntimeConfig` returns the configured Desktop feature flags, active
map selector, compiled browser URL and adapter configuration needed by
`m-desktop`. Physical interactables and runtime lifecycle are owned by
`m-desktop`.

`OpenClientFrame`, `CloseClientUI`, `ToggleClientFrame` and
`PushClientInitialData` are the generic UI-host bridge used by `m-desktop`.
The `Desktop*` names remain compatibility aliases and should not be used by new
integrations.

`DesktopAttachSpatialUI`, `DesktopDetachSpatialUI` and `DesktopSetNativeSpatialState` are internal callback-registry bridge operations used by `m-desktop`; gameplay resources must not call them. `DesktopActivateSpatial`, `DesktopActivateNativeSpatial` and `DesktopDeactivateSpatial` remain compatibility proxies and new integrations should call `m-desktop` directly.

The three marker exports are also compatibility proxies to `m-desktop`. `m-phone` no longer owns camera, material, virtual-pointer or spatial WebUI lifecycle code.

## CreatorLink trusted API

- `HandleCreatorLinkRequest`
- `HandleCreatorLinkWidgetRequest`
- `GetCreatorLinkPlayerBenefits`
- `GetCreatorLinkActiveEntitlement`
- `ReviewCreatorLinkBenefitRequest`
- `GetCreatorLinkPartnerBenefitRequests`
- `GetCreatorLinkPartnerApplications`
- `ReviewCreatorLinkPartnerApplication`
- `RecordCreatorLinkTransaction`
- `SettleCreatorLinkTransaction`
- `ReverseCreatorLinkTransaction`

Review, transaction, settlement, and reversal exports are restricted to trusted server resources. LIX purchase and admin-panel integrations remain provisional/TODO until their authoritative services exist.

## Architecture

See [COMPONENTS.md](COMPONENTS.md) for ownership boundaries. Gameplay systems such as banking, courier, jobs, and trucker should expose their own service APIs; `m-phone` should retain only device presentation and compatibility wrappers.
