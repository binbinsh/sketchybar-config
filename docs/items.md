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
  - CPU/GPU/MEM graphs with real-time percentage and temperature display.
  - Left-click on any graph toggles a centered popup showing:
    - **CPU section**: Top 10 processes by CPU usage (name + %)
    - **MEM section**: Top 10 processes by memory usage (name + size in KB/MB/GB)
  - Popup title click refreshes the process list.
  - Driven by the native helper `helpers/system_stats/bin/system_stats` (event: `system_stats_update`).
  - See `docs/system_stats.md` for details.

- `items/weather.lua`
  - Weather icon + temperature (°C). Left-click toggles a centered popup; right-click opens the macOS Weather app.
  - Popup displays:
    - **Current conditions**: Updated time, Location (reverse geocoded), Condition (icon + English + Chinese), Temperature, Feels like
    - **Humidity**: Visual bar indicator (█░░░░░░░░░ XX%)
    - **Details**: Wind speed (m/s), Pressure (hPa), Sunrise/Sunset (local time), Time zone
    - **5-DAY OUTLOOK**: Daily forecast with weekday (周一-周日), weather icon, high/low temps
    - **Weather alerts**: Displayed with ⚠️ icon when active
  - Popup title click forces refresh (ignores TTL).
  - Uses OpenWeather OneCall API 3.0 with reverse geocoding via Nominatim for location names.
  - Requires an OpenWeather API key in Keychain and uses the location helper.
    - Store key: `security add-generic-password -a "$USER" -s OPENWEATHERMAP_API_KEY -w '<YOUR_API_KEY>' -U`
    - Location helper details: `docs/location.md`
  - Caches under `~/.cache/sketchybar/` (TTL configurable via `WEATHER_CACHE_TTL`, `WEATHER_LOCATION_TTL`).

- `items/wifi.lua`
  - Wi-Fi icon + throughput graph (matching system_stats style). Shows combined throughput rate (Kbps/Mbps/Gbps).
  - Left-click toggles a centered popup; right-click opens Network settings.
  - Popup displays:
    - **Connection**: Status, SSID, Hostname, IP, Subnet mask, Router, Download/Upload speeds
    - **Wi-Fi details** (when available): BSSID, PHY Mode, Channel, Security, Interface Mode, Signal/Noise, Transmit Rate/Power, MCS Index, Country Code
    - **Scamalytics**: IP risk score for public IP (when configured)
  - Throughput is event-driven via `helpers/network_load/bin/network_load` (event: `network_update`).
  - Popup details are fetched via `helpers/network_info/.../SketchyBarNetworkInfoHelper`.
  - If SSID is missing, it may request Location permission (through the location helper).
  - Scamalytics IP risk is shown when `SCAMALYTICS_API_HOST` env is set, or when both `SCAMALYTICS_API_KEY` and `SCAMALYTICS_API_USER` are present in Keychain.
    - Store key: `security add-generic-password -a "$USER" -s "SCAMALYTICS_API_KEY" -w "<YOUR_API_KEY>" -U`
    - Store user: `security add-generic-password -a "$USER" -s "SCAMALYTICS_API_USER" -w "<YOUR_API_USER>" -U`
  - Optional env: `WIFI_INTERFACE` (defaults to `en0`).

- `items/battery.lua`
  - Battery percent widget with charging icon. Left-click toggles a centered popup; right-click opens Battery settings.
  - Popup sections:
    - **STATUS**: Status (Charging/Discharging/Not charging/Charged), Charge %, Power source (with wattage), Time remaining
    - **POWER CONTROLS**: Charging toggle, Adapter toggle (requires sudo + `battery_control` helper)
    - **CHARGE LIMIT**: Draggable slider (20-100%) + Auto Maintain toggle with hysteresis logic
    - **BATTERY DETAILS**: Health %, Cycle count (current/design), Capacity (current/max mAh), Design/Nominal capacity, Temperature
    - **ELECTRICAL**: Voltage/Current, Power draw (battery/system), Cell voltages with delta
    - **ADVANCED**: SoC (smart), Pack reserve, Charger info with reason codes, System input, Adapter info, Device/FW, Flags, Serial
  - Auto Maintain mode: Automatically enables/disables charging to maintain target percentage with 2% hysteresis.
  - State persisted to `states/battery_control.lua` (target, enabled, history).
  - History recorded every 10 minutes (max 144 points = 24h).
  - Driven by the native helper `helpers/battery_info/bin/battery_info`.
  - Power control requires `helpers/battery_control/bin/battery_control` with sudo privileges.

- `items/volume.lua`
  - Output volume widget with icon. Scroll to adjust volume (throttled; hold Ctrl for fine 1% steps).
  - Left-click toggles a centered popup with draggable slider; right-click opens Sound settings.
  - Popup displays:
    - **Volume slider**: Draggable, reflects current level
    - **Level**: Percentage + dB value
    - **Mute**: Toggle (click to mute/unmute)
    - **OUTPUT section**: Device name, Transport (󰂯 Bluetooth/󰕓 USB/󰌢 Built-in/etc.), Sample Rate (kHz), Channels (Stereo/Mono), Format (16-bit/24-bit/Hi-Res)
    - **INPUT section**: Device name, Transport, Sample Rate, Channels, Input Level (visual bar)
  - Volume changes trigger `volume_change` event for real-time updates.

- `items/calendar.lua`
  - Date/time widget (updates frequently, but avoids shell polling).
  - Left-click opens Control Center.

- `items/pomodoro.lua`
  - Pomodoro timer with stacked labels. Left-click start/pause; right-click reset; middle-click edits durations.
  - State is persisted to `states/pomodoro_state.lua`.

- `items/1password.lua`
  - 1Password launcher. Left-click triggers 1Password Quick Access; right-click opens the app.

- `items/ccadapter.lua`
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
