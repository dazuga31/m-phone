# Troubleshooting m-phone

## Phone does not open

1. Confirm `Config.Features.Phone = true`.
2. Press the default `Up` key.
3. Check that `qb-core` and `m-phone` both reached their startup-ready logs.
4. Close another UI that may own the input mode.
5. Check for a key-binding conflict.

The default controls are listed in [CONTROLS.md](CONTROLS.md).

## An optional App reports a missing export

- Disable its `Config.Features` flag when the provider is not installed.
- Confirm the configured resource name matches the actual directory.
- Start the provider before `m-phone`.
- Use that provider's public API instead of its database or globals.

HELIX export proxies are not a reliable package-existence probe. Startup
dependency lines describe configuration; they are not proof that a provider is
healthy.

## Bank balance works but history is empty

This is expected with `Config.Use.Bank = "qb"`. Base qb-core provides live cash
and bank values but no authoritative transaction ledger. Select `mbank` and
install `m-banking` for persistent accounts, history, and recipients.

## Contacts, SMS, or calls do not reach another player

- Confirm both players have generated phone numbers in qb-core metadata.
- Confirm the recipient is online for operations that require an online
  controller.
- Review `Config.Communications` limits and rate limits.
- Check the voice provider and channel range when only call audio fails.

## Camera upload fails

1. Confirm Camera is enabled.
2. Copy `camera_storage_local.example.lua` to
   `camera_storage_local.lua`.
3. Replace `CHANGE_KEY` in the local file and corresponding service.
4. Check upload-ticket and delete endpoints.
5. Keep the populated local file untracked.

The current alpha production path is the custom remote-storage adapter. Other
storage fields are compatibility or reserved configuration unless your build
implements them.

## Item images are missing

- Set `Config.InventoryImages.Provider` explicitly.
- Check its `BaseUrl`, extension, and browser accessibility.
- Confirm the image filename matches the item id.
- Add an `Overrides` entry for exceptional assets.
- Configure a `FallbackUrl`.

## An App or Widget is missing

- Confirm `Config.SDK.Enabled` or `Config.WidgetSDK.Enabled`.
- Confirm the manifest is registered on the correct runtime side.
- Check `surfaces.phone` or `surfaces.tablet`.
- Check `defaultInstalled`, installation state, and feature filtering.
- Confirm the provider resource and WebUI entry path exist.

## Database initialization fails

Preserve `m-phone.sqlite` before troubleshooting. Find the first SQLite/schema
error, verify persistence-directory write access, and follow
[DATABASE.md](DATABASE.md). Do not delete the database as the first fix.

## WebUI appears immediately or cannot close

Check the client open/close lifecycle and any external host calling the generic
UI bridge. A visible compiled page in a normal browser does not prove HELIX
focus and input behavior. Capture the first m-phone client logs before and
after the UI becomes visible.

## Reporting a bug

Include:

- m-phone version and commit;
- HELIX Studio/client/dedicated build;
- World id and `Config.ActiveMap`;
- enabled feature and provider settings;
- exact reproduction steps;
- the first relevant error and surrounding log lines;
- whether the issue reproduces in Studio and standalone client.

Use [GitHub Issues](https://github.com/dazuga31/m-phone/issues) for normal
bugs. Use the private process in [SECURITY.md](SECURITY.md) for vulnerabilities.
