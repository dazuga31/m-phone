# Pull request

## Summary

Describe the problem, ownership boundary, and focused solution.

## Runtime contracts

List any changed config fields, exports, manifests, events, database state, or
provider requirements. Write `None` when no contract changes.

## Validation

- [ ] Changed Lua files parse successfully.
- [ ] Changed JavaScript files pass `node --check`.
- [ ] Relative Markdown links pass validation.
- [ ] The affected flow was tested in HELIX Studio.
- [ ] Standalone client or dedicated server was tested when relevant.

## Safety

- [ ] No credentials, databases, generated player media, or logs are included.
- [ ] Server-side mutations validate identity, ownership, amounts, and rate limits.
- [ ] Added media is owned or licensed for redistribution.
- [ ] Relevant documentation and `CHANGELOG.md` are updated.
