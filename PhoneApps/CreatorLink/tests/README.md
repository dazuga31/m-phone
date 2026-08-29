# CreatorLink tests

`domain_spec.lua` runs deterministic Lua checks for:

- creator-code normalization;
- quantity splitting by inventory stack size;
- HELIX fee, server net, and creator commission calculations;
- multi-row inventory grants;
- complete and partial-grant rollback.

Enable startup execution only through the test flag in `PhoneApps/CreatorLink/config.lua`. Production should keep automatic tests disabled.

The tests use an in-memory fake inventory provider and do not mutate live player data.
