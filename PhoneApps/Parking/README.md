# Parking Phone App

This App lets a player buy or extend parking for an owned vehicle in a configured four-digit zone.

## Server validation

- Normalize and verify the zone ID against `Config.ParkingApp.Zones`.
- Verify the plate belongs to the current QBCore character.
- Require an active bank account.
- Enforce time steps and zone maximum duration.
- Apply weekend discounts, peak-period fees, and free-zone rules.
- Prevent one vehicle from holding active parking in a different zone.
- Use a required `requestId` for idempotent payment retries.

The server calculates every quote and persists the resulting session. WebUI prices and expiry values are untrusted.

The current banking path uses the device banking bridge/database compatibility layer. A future extraction should call the selected bank provider directly without changing the App UI contract.
