# Rewards device service

This module formats reward and bank notifications and contains guarded developer test actions.

## Files

- `rewards_client.lua` sends system-chat entries and renders reward/bank feedback.
- `rewards_server.lua` validates configured development mutations and coordinates provider calls.
- `rewards_server_shared.lua` contains shared notification dispatch.

Test payout and debit handlers must remain disabled unless `Config.Developer.AllowTestMutations == true`. They are development tools, not a production reward API.

Inventory grants, bank mutations, and entitlements remain authoritative in their owning resources. New production reward systems should expose a dedicated server API rather than expanding these test events.
