# CreatorLink widgets

CreatorLink provides two optional widgets:

- `mphone.creatorlink-support` - active creator code and reward-cycle status.
- `mphone.creatorlink-pulse` - partner level, creator credits, and campaign momentum.

Both support `minimal`, `medium`, and `wide` layouts and reuse the shared AppWidgets renderer. Their server handlers delegate to the authoritative CreatorLink request service.

The Pulse widget requires partner data; non-partners should receive a controlled unavailable/locked state rather than fabricated statistics.

See [../../PhoneApps/CreatorLink/README.md](../../PhoneApps/CreatorLink/README.md) for domain rules and API restrictions.
