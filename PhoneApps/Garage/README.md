# Garage Phone App

The Garage App presents a read-only list of vehicles owned by the current QBCore character.

## Data sources

- `qb-core` resolves the player, shared vehicle catalog, and `player_vehicles` rows.
- `m-properties` supplies public and owned garage labels.
- `m-vehicleshop` supplies vehicle and brand media when available.

The App returns model, display name, plate, garage, state, condition, distance, and finance summary. Vehicle spawn, storage, transfer, and garage access remain in `m-properties` or the authoritative vehicle domain.

`m-phone:garage:*` events are internal presentation transport and are not a public vehicle API.
