# CreatorLink Phone App

CreatorLink is the optional creator/media-partner attribution, reward, progression, benefit, and commission feature hosted by `m-phone`.

## Player flow

- Discover an active creator code.
- Review the reward and attribution period.
- Confirm activation; an active code cannot be replaced until its configured period expires.
- Receive first/repeat rewards through the inventory and core adapters.
- View history, entitlements, and partner-facing progression data.

## Partner and trusted-service flow

- Track level, creator credits, activations, and transaction-derived commission.
- Submit or review configured benefit requests.
- Submit/review creator applications.
- Record, settle, or reverse LIX transactions through trusted server exports.

The authoritative HELIX LIX purchase API and administration panel do not exist yet. Transaction and review integrations are therefore provisional/TODO and must not be treated as proof of a real purchase or staff authorization.

## Files

- `config.lua` - attribution duration, rewards, finance percentages, levels, benefits, partner seeds, manifests, and future integration flags.
- `domain.lua` - pure normalization, stack splitting, and commission calculations.
- `database.lua` - CreatorLink persistence.
- `inventory_adapter.lua` - transactional reward grant/rollback through `m-inventory`.
- `bridge/` - core-specific identity, cash, and database adapters.
- `server.lua` - authoritative requests and trusted exports.
- `client.lua` - App SDK/WebUI transport.
- `tests/` - pure domain and inventory rollback checks.

## API and security

Trusted exports are documented in [../../API.md](../../API.md) and [../../EXPORTS.md](../../EXPORTS.md). Review, transaction, settlement, and reversal exports must be restricted to trusted server resources; never expose them directly to WebUI.

Failed code attempts are rate-limited. Rewards use stable claim identities and must roll back partial inventory grants.
