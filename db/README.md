# Internal device database modules

This folder extends the shared `m-phone` database object with focused persistence helpers.

## Modules

- `chat.lua` - conversations, messages, unread state, and system messages.
- `communications.lua` - phone profiles, phone numbers, contacts, calls, and communication preferences.
- `documents.lua` - legacy device-side document references and status helpers.
- `jobs.lua` - legacy Trucker/Courier schema compatibility during domain extraction.
- `parking.lua` - Phone Parking App sessions and quotes.
- `photos.lua` - camera/gallery metadata.

Every file returns an `Apply(DB)` function and is loaded by the parent database bootstrap. These functions are internal and are not public exports.

Gameplay resources must use [../API.md](../API.md) or the owning domain resource. Direct SQL access couples consumers to migration tables and is unsupported.
