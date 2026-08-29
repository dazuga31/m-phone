# Courier Phone App

This folder is the narrow Phone presentation for Courier assignments, status, completion controls, and invoice printing.

`config.lua` selects the provider resource (`m-courier`). Client and server files translate WebUI actions to the Courier adapter and return UI-ready results.

## Internal actions

- Load Courier data.
- Accept, complete, or cancel a job.
- Print the authoritative invoice for an owned assignment.

Job availability, ownership, reward, progression, and invoice issuance are validated by `m-courier`. See [../../../m-courier/API.md](../../../m-courier/API.md).
