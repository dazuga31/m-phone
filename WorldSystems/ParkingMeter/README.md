# Parking Meter world system

This module owns the Lua side of the physical Parking Meter Blueprint/native display.

## Responsibilities

- Spawn or bind configured meters.
- Open the camera-focused interaction session.
- Handle keyboard/button input and reusable button animation.
- Calculate selected time and price from server configuration.
- Lock a meter during payment, debit the configured bank provider, persist active time, and issue a receipt.
- Return current state to every player interacting with the same meter.

## Files

- `client.lua` owns focus, input, Blueprint component updates, and presentation.
- `button_animation.lua` animates an independent button component using relative location.
- `server.lua` owns reservations, locks, payment, persistence, and receipt orchestration.

`m-phone:parkingMeter:*` events are internal world-system events. Payment amount, active expiry, and meter state are always resolved on the server.
