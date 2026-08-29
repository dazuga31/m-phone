# Camera and Gallery Phone Apps

This module owns HELIX camera capture, selfie/rear-camera state, gallery metadata, and configurable photo storage.

## Files

- `camera_client.lua` creates the native capture, applies camera controls, captures an image, and bridges Camera/Gallery WebUI requests.
- `camera_server.lua` validates photo list/save/delete requests and enforces `Config.Camera.MaxPhotos`.
- `camera_storage_server.lua` loads private server storage settings.
- `camera_storage_local.example.lua` documents the local secret/config shape.

## Configuration

`Config.Camera` controls capture resolution, exposure, timeout, photo limit, and storage mode. Custom remote storage may use upload-ticket and delete endpoints; local storage uses the configured HELIX directory.

Never commit active storage credentials in a distributable package. Keep `camera_storage_local.lua` private and derive a sanitized deployment file from the example.

## Internal bridge

Browser handlers use `camera:*` and `gallery:*`; server replies use `m-phone:camera:result`. External resources should use the device API in [../../API.md](../../API.md), not these internal events.
