# Courier integration adapter

This adapter calls the Courier provider selected by `Config.Courier.Resource` (default `m-courier`).

It normalizes provider failures for data reads, job acceptance, completion, cancellation, and invoice printing. It also exposes trusted internal player-ID reads used by widgets and presentation state.

The adapter contains no Courier persistence. Use `m-courier/API.md` in the
separately distributed provider resource for the authoritative public API.
