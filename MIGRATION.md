# Migrating m-phone

## Fresh installation

For a new server:

1. Install the exact `m-phone` directory name.
2. Start `qb-core` before `m-phone`.
3. Enable only integrations whose provider resources are installed.
4. Keep `Config.LegacyLocalDomainSchema = false`.
5. Start the World and verify the dependency and database startup logs.

## Updating from 0.9.0-alpha

`0.9.1-alpha` is a documentation and release-hardening update. It does not
introduce a destructive database migration.

Always back up `m-phone.sqlite` and any local camera configuration before
replacing files.

## Migrating an older all-in-one build

Older development builds may still contain local Shop, Courier, or Trucker
tables.

1. Stop the World and back up its full persistence directory.
2. Install the domain resource that now owns the feature, such as
   `m-business`, `m-courier`, or `m-trucker`.
3. Temporarily set `Config.LegacyLocalDomainSchema = true` only while the old
   tables are still required.
4. Verify the new provider independently before enabling its Phone App.
5. Move data using a reviewed one-off migration designed for both schemas.
6. Disable the legacy switch after every enabled feature reads its
   authoritative provider.

`m-phone` does not automatically transfer legacy rows to another resource and
does not delete the old tables. Do not remove them until ownership, balances,
history, and identifiers have been verified.

## Configuration migration

Compare the new `config.lua` with the previous version rather than replacing it
blindly. Pay particular attention to:

- `Config.Features`
- `Config.Use.Core`
- `Config.Use.Bank`
- provider resource names
- `Config.Inventory` and `Config.InventoryImages`
- `Config.SDK` and `Config.WidgetSDK`
- `Config.ActiveMap`
- camera storage local overrides

## Downgrade

Downgrades are unsupported without a matching pre-upgrade backup. An older
runtime may not understand columns or state written by a newer alpha release.

## Local secrets

`PhoneApps/Camera/camera_storage_local.lua` is ignored by Git. Preserve it
separately when replacing or recloning the resource, and never publish it.
