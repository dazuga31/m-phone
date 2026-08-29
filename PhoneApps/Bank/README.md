# Bank Phone and Tablet App

This module is the lightweight Phone/Tablet presentation bridge for account creation, profile/history reads, recipient validation, transfers, and business funding.

The server delegates banking operations to [../../Integrations/Banking/README.md](../../Integrations/Banking/README.md) and business funding to `m-business`. It does not own balances or transaction tables.

Browser handlers and `m-phone:bank*` events are internal compatibility contracts for the compiled renderer. The wide-screen ATM adapter is owned by `m-desktop`; external resources should use the authoritative provider API documented in `m-banking/API.md`.

Always treat transfer accounts, names, references, amounts, and request IDs from WebUI as untrusted input.
