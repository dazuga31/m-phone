# CreatorLink core bridges

This folder isolates core-specific identity, cash, and database behavior from the CreatorLink domain.

- `qb.lua` implements player snapshot resolution, cash add/remove, and database access through `qb-core` exports.
- `m.lua` is an explicit placeholder that returns `m_core_not_implemented`.

`PhoneApps.CreatorLink.config.Core` selects the bridge. New core support belongs in a new adapter with the same small function surface; do not add core conditionals throughout CreatorLink domain code.

Bridge functions are internal modules, not public exports.
