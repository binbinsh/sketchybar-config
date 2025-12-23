# Items

Detailed reference for items and widgets defined in `items/`.

- [Overview](#overview)
- [Widgets and Integrations](#widgets-and-integrations)
- [Shortcuts](#shortcuts-shortcutslua)
- [Volume](#volume-volumelua)
- [GitHub](#github-githublua)
- [System Stats](#system-stats-system_statslua)
- [Weather](#weather-weatherlua)
- [Now Playing](#now-playing-now_playinglua)
- [WeChat](#wechat-wechatlua)

## Overview

- Front App (`front_app.lua`): shows the active app name; click toggles the `menus` and `spaces` brackets via the `swap_menus_and_spaces` event.
- Pomodoro (`pomodoro.lua`): minimal timer; left-click start/pause, right-click resets the current phase; auto-advances with notifications.
- Widgets: app integrations and interactive widgets are documented below.

## Widgets and Integrations

Quick reference for the app integrations and interactive widgets in this directory.

## Shortcuts (`shortcuts.lua`)

- A row of shortcut icons (Clipboard, Dictionary, LM Studio, 1Password, Quantumult X, Synergy, Time Machine, Ubuntu, WeChat) managed in one widget file.
- Left-click each icon to open its own centered popup; right-click does nothing.

## Volume (`volume.lua`)

- Shows the current output volume and an icon.
- Click opens SoundSource; right-click opens Sound settings.

## GitHub (`github.lua`)

- Shows a GitHub badge for new issues created since you last opened issues, plus a popup with repo/issue/PR counts.
- Left-click toggles the popup; right-click opens GitHub Issues and clears the new-issue badge.
- Setup: install GitHub CLI and run `gh auth login`.
- Ensure auth scopes include `repo` for private repos and `read:org` if you include orgs with private repos.
- Optional: set `GITHUB_ORGS` (comma-separated) to include org-owned repositories in the counts.

## WeChat (`wechat.lua`)

- Shows unread count from the Dock badge; click opens or activates WeChat.
- Setup: install the macOS app (`com.tencent.xinWeChat`), enable App Icon Badges (System Settings -> Notifications -> WeChat), and allow `osascript` in Accessibility (System Settings -> Privacy & Security -> Accessibility).

## System Stats (`system_stats.lua`)

- Shows CPU/GPU usage with current temperatures plus memory usage, driven by the native helper in `helpers/system_stats`.

## Weather (`weather.lua`)

- Uses OpenWeather One Call API 3.0 for current conditions; shows condition, temperature, feels like, humidity, wind, pressure, time zone, sunrise, and sunset.
- Left-click toggles a centered popup titled with your location (`<place>` lat, lon) and a refresh affordance; click the title to refresh immediately; right-click opens the OpenWeather map for your coordinates (falls back to the macOS Weather app).
- Auto-refreshes hourly; coordinates come from the location helper (see `location.md`) and are reverse-geocoded via OpenStreetMap.
- Setup: register an API key at https://openweathermap.org/api (free tier is 1,000 calls/day), then store it in Keychain:

```bash
security add-generic-password -a "$USER" -s OPENWEATHERMAP_API_KEY -w '<YOUR_API_KEY>' -U
```

The widget reads it with `security find-generic-password -a "$USER" -s OPENWEATHERMAP_API_KEY -w`. New keys can take 1-2 hours to activate.

## Now Playing (`now_playing.lua`)

- Displays track metadata (title, artist, album) for Apple Music, Spotify, and YouTube Music (via the browser bridge).
- See `now_playing.md` for the Native Messaging bridge and installation steps.
