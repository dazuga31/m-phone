# Jobs integration adapter

This adapter forwards Job Centre profile, submission, and latest-application reads to `Config.Jobs.Resource` (default `m-jobs`).

Unavailable or malformed provider responses are normalized to `{ ok = false, error = "jobs_unavailable" }` or another stable provider error.

It has no public exports and owns no application state. See `m-jobs/API.md` in
the separately distributed provider resource.
