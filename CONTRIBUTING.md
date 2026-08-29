# Contributing to m-phone

## Scope

`m-phone` owns the Phone and Tablet shells, device presentation, communication
features, the compiled browser host, and narrow compatibility bridges.
Authoritative banking, business, jobs, courier, trucker, property, and Desktop
gameplay should remain in their dedicated resources.

The main React/TypeScript source is not included in this runtime repository.
Do not hand-edit generated or minified files under `web/assets`.

## Changes

- Keep changes focused and compatible where practical.
- Use explicit feature flags for optional providers.
- Validate every mutation server-side.
- Never commit tokens, passwords, player media, databases, or local camera
  configuration.
- Include only assets that you own or are permitted to redistribute.
- Update the relevant Markdown contract when changing config, exports, storage,
  controls, or SDK behavior.

## Validation

Parse changed Lua files with a Lua parser. Maintainers currently use:

```powershell
npx --yes luaparse@0.3.1 path\to\file.lua
```

Check template JavaScript with:

```powershell
node --check path\to\file.js
```

The maintainer workspace also provides:

```powershell
& D:\UE_Projects\MyProject\Tools\AITools\ResourceDocsAudit\ResourceDocsAudit.ps1 `
  -ScriptsRoot D:\UE_Projects\MyProject\Scripts
```

Contributors outside that workspace can run equivalent Markdown-link,
manifest, Lua-parse, and export-documentation checks.

Static validation does not prove HELIX runtime behavior. Test the changed flow
inside HELIX Studio and, when relevant, standalone client or dedicated server.

## Pull request checklist

- Explain the problem and the ownership boundary.
- List changed runtime contracts.
- Include focused reproduction and verification steps.
- Update `CHANGELOG.md` for user-visible changes.
- Confirm no secrets, databases, generated media, or unlicensed assets were
  added.
- Confirm required and optional dependencies remain accurate.

Security issues must use [SECURITY.md](SECURITY.md), not a public pull request.
