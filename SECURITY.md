# Security

## Credentials

Never commit API keys, tokens, passwords, Webhooks, private endpoints, databases,
or generated player media.

Camera credentials belong in
`PhoneApps/Camera/camera_storage_local.lua`. This file is ignored by Git. Start
from `camera_storage_local.example.lua` and keep the populated file only on the
server or development machine.

## Server authority

Treat all WebUI and client payloads as untrusted. Purchases, balances, ownership,
rewards, jobs, documents, and inventory changes must be validated server-side.

## Reporting

Do not publish exploit details or credentials in a public issue. Submit a
[private security advisory](https://github.com/dazuga31/m-phone/security/advisories/new)
with the affected version, reproduction steps, impact, and any proposed fix.

Private vulnerability reporting is enabled for the GitHub repository. If the
form is unavailable, open a public issue containing no exploit details and ask
the maintainer for a private contact channel.
