# m-phone Database

## Storage

`m-phone` initializes its SQLite database automatically:

```text
m-phone.sqlite
```

The file is created in the active HELIX World persistence directory through
`Database.Initialize("m-phone.sqlite")`. Its absolute host path is controlled by
HELIX and can differ between Studio, client, and dedicated server Worlds.

## Current tables

The current runtime manages:

- `Players`
- `PlayerSettings`
- `ChatConversations`
- `ChatMessages`
- `PhoneProfiles`
- `PhoneContacts`
- `PhoneContactFlags`
- `PhoneSmsReceipts`
- `PhoneCallHistory`
- `PhonePhotos`
- `PlayerDocuments`
- `ParkingSessions`

When `Config.LegacyLocalDomainSchema = true`, migration-only compatibility
tables are also initialized:

- `ShopProducts`
- `OwnedShops`
- `OwnedShopProducts`
- `OwnedShopLedger`
- `OwnedShopTransactions`
- `ShopSupplyOrders`
- `CourierProfiles`
- `CourierJobs`
- `CourierInvoices`
- `TruckerProfiles`
- `TruckerOrders`

New installations should keep the legacy switch disabled. Authoritative
business, courier, and trucker persistence belongs to their dedicated
resources.

## Schema behavior

Startup schema guards create missing tables and add compatible missing columns.
They do not intentionally remove existing tables or perform destructive data
migrations.

Direct SQL access by third-party resources is unsupported. Use the public
exports of `m-phone` or the resource that owns the relevant domain.

## Backup

Before an upgrade:

1. Stop the World or dedicated server.
2. Locate the active World persistence directory.
3. Copy `m-phone.sqlite` to a dated backup outside that directory.
4. Keep the backup until the updated resource has completed a full runtime
   test.

A factory reset in the WebUI is not a database backup and does not replace this
procedure.

## Recovery

If initialization fails:

1. Preserve the failing database before changing it.
2. Review the first schema or SQLite error in the server log.
3. Confirm the process can write to the active persistence directory.
4. Test with a copied database, not the only production copy.
5. Report the m-phone version, HELIX build, active World id, and full first
   error.

See [MIGRATION.md](MIGRATION.md) and
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).
