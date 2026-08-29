# m-phone Default Controls

## Phone

| Key | Action |
| --- | --- |
| `Up` | Toggle the Phone |
| `Escape` | Close the active m-phone UI |
| `Backspace` | Close the active m-phone UI |
| `F3` | Debug identity probe when `Debug = true` |

These defaults are bound in client Lua and are not exposed as public config
options in `0.9.1-alpha`.

## Parking meter

| Key | Action |
| --- | --- |
| `E` | Open the nearest meter interaction |
| `1` | Add one configured time step |
| `2` | Confirm and pay |
| `3` | Back or cancel |
| `4` | Remove one time step when allowed |
| `Escape` / `Backspace` | Leave the meter view |

The parking meter uses its physical buttons and does not require a viewport
cursor.

## Input conflicts

HELIX UI input mode and other resources can temporarily own keyboard or mouse
input. If a control does not respond, close the active native/WebUI screen and
check for another resource binding the same key.
