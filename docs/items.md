# Items

This document describes the items defined in `items/` and loaded by `items/init.lua`.

## Overview

Most items are implemented as **compact, bracket-less widgets** (for performance and consistent spacing). Some items use the shared centered popup helper (`center_popup.lua`).

There is also a global performance guard (`mission_control.lua`) that sets `_G.SKETCHYBAR_SUSPENDED` during Space transitions; many items skip expensive updates while that flag is true.

## Loaded by default (`items/init.lua`)

- `items/apple.lua`
  - Apple logo on the left; click opens the Apple menu (via `helpers/menus/bin/menus -s 0`).
  - Uses a bracket background to visually mask the native menu bar behind it.

- `items/menus.lua`
  - Renders the current app menu items on the left; click selects a menu entry.
  - Updates on `front_app_switched` with debounce + short retries to avoid stale menus during app transitions (notably for some Electron apps).
  - Driven by the native helper `helpers/menus/bin/menus`.

- `items/spaces.lua`
  - Space switcher (right side): shows Space number + a user-defined name.
  - Left-click switches Space (Command+Number); right-click renames and persists to `states/spaces_names.lua`.
  - Uses the native helper `helpers/spaces_count/bin/spaces_count` to detect the Space count.

- `items/system_stats.lua`
  - CPU/GPU graphs with temperatures + memory graph.
  - Driven by the native helper `helpers/system_stats/bin/system_stats` (event: `system_stats_update`).
  - See `docs/system_stats.md` for details.

- `items/weather.lua`
  - Weather icon + temperature (°C). Left-click toggles a centered popup; right-click opens the macOS Weather app.
  - Popup title click forces refresh (ignores TTL).
  - Requires an OpenWeather API key in Keychain and uses the location helper.
    - Store key: `security add-generic-password -a "$USER" -s OPENWEATHERMAP_API_KEY -w '<YOUR_API_KEY>' -U`
    - Location helper details: `docs/location.md`
  - Caches under `~/.cache/sketchybar/` (TTL configurable via `WEATHER_CACHE_TTL`, `WEATHER_LOCATION_TTL`).

- `items/wifi.lua`
  - Wi‑Fi throughput widget (stacked upload/download numbers). Left-click toggles a centered popup; right-click opens Network settings.
  - Throughput is event-driven via `helpers/network_load/bin/network_load` (event: `network_update`).
  - Popup details are fetched via `helpers/network_info/.../SketchyBarNetworkInfoHelper`.
  - If SSID is missing, it may request Location permission (through the location helper).
  - Scamalytics IP risk (public IP) is shown when both `SCAMALYTICS_API_KEY` and `SCAMALYTICS_API_USER` are present in Keychain.
    - Store key: `security add-generic-password -a "$USER" -s "SCAMALYTICS_API_KEY" -w "<YOUR_API_KEY>" -U`
    - Store user: `security add-generic-password -a "$USER" -s "SCAMALYTICS_API_USER" -w "<YOUR_API_USER>" -U`
  - Optional env: `WIFI_INTERFACE` (defaults to `en0`).

- `items/battery.lua`
  - Battery percent widget. Left-click toggles a centered popup with detailed battery telemetry; right-click opens Battery settings.
  - Driven by the native helper `helpers/battery_info/bin/battery_info`.

- `items/volume.lua`
  - Output volume widget. Scroll changes volume (events are coalesced); left-click opens SoundSource; right-click opens Sound settings.
  - Uses `helpers/menus/bin/menus` to click the SoundSource menu extra when possible.

- `items/calendar.lua`
  - Date/time widget (updates frequently, but avoids shell polling).
  - Left-click opens Control Center.

- `items/pomodoro.lua`
  - Pomodoro timer with stacked labels. Left-click start/pause; right-click reset; middle-click edits durations.
  - State is persisted to `states/pomodoro_state.lua`.

- `items/1password.lua`
  - 1Password launcher. Left-click triggers 1Password Quick Access; right-click opens the app.

- `items/cc_adapter.lua`
  - CC Adapter menubar shortcut. Left-click opens the CC Adapter tray menu.

## Optional items (not loaded by default)

- `items/lock.lua`
  - Lock-screen shortcut (Command+Control+Q).
  - To enable, add `require("items.lock")` to `items/init.lua`.

## Building native helpers

From the config root:

```bash
make -C helpers
```
