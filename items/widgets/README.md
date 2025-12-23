# Widgets & Integrations

Quick reference for the app integrations and interactive widgets in this directory.

- [LM Studio](#lm-studio-lm_studiolua)
- [Shortcuts](#shortcuts-shortcutslua)
- [Clipboard](#clipboard-clipboardlua)
- [Dictionary](#dictionary-dictionarylua)
- [Volume](#volume-volumelua)
- [Quantumult X](#quantumult-x-quantumultxlua)
- [1Password](#1password-onepasswordlua)
- [WeChat](#wechat-wechatlua)
- [iStat Menus](#istat-menus-istat_menuslua)
- [Time Machine](#time-machine-time_machinelua)
- [Synergy](#synergy-synergylua)
- [Weather](#weather-weatherlua)
- [Now Playing](#now-playing-now_playinglua)

## LM Studio (`lm_studio.lua`)

- Hover tints the icon; left-click opens a popup listing installed models (from `lms ls`) so you can load/start one; the last row unloads all models; right-click opens the LM Studio app.
- Setup: install the CLI with `~/.lmstudio/bin/lms bootstrap` (or ensure `lms` is on `PATH`); the popup hints if the CLI is missing.

## Shortcuts (`shortcuts.lua`)

- Single launcher icon that shows a popup summary for Clipboard, Dictionary, LM Studio, 1Password, Quantumult X, Synergy, Time Machine, Ubuntu, and WeChat.
- Left-click toggles the popup; right-click does nothing.

## Clipboard (`clipboard.lua`)

- Hover tint; left-click opens Raycast Clipboard History; right-click opens Raycast Ask Clipboard.
- Requires the Raycast Clipboard History extension (no fallback).

## Dictionary (`dictionary.lua`)

- Hover tint; left-click runs Instant Translate on the current selection; right-click opens Raycast Quick Translate.
- Requires the Raycast "Translate" extension (`gebeto/translate`).

## Volume (`volume.lua`)

- Shows the current output volume and an icon.
- Click opens SoundSource; right-click opens Sound settings.

## Quantumult X (`quantumultx.lua`)

- Hover tint; left-click toggles a popup with Public IP, Location, and ISP (queried from `ipinfo.io` via `curl`); right-click opens Quantumult X.

## 1Password (`onepassword.lua`)

- Hover tint; left-click opens 1Password Quick Access (Cmd+Shift+Space); right-click opens the app.

## WeChat (`wechat.lua`)

- Shows unread count from the Dock badge; click opens or activates WeChat.
- Setup: install the macOS app (`com.tencent.xinWeChat`), enable App Icon Badges (System Settings -> Notifications -> WeChat), and allow `osascript` in Accessibility (System Settings -> Privacy & Security -> Accessibility).

## iStat Menus (`istat_menus.lua`)

- Automatically aliases the Combined menu extra when available and groups it; click opens Activity Monitor.
- Setup: enable the Combined menu extra in iStat Menus so it can be aliased.

## Time Machine (`time_machine.lua`)

- Minimal widget with a popup showing `tmutil status`, latest backup timestamp, and actions (start/stop backup, open destination, open Time Machine); right-click opens Time Machine settings.
- `tmutil latestbackup` may require Full Disk Access for the running `sketchybar` binary; if it's blocked, the widget falls back to `LastBackupActivity` from `/Library/Preferences/com.apple.TimeMachine.plist` (restart SketchyBar after changing privacy permissions).

## Synergy (`synergy.lua`)

- Idle icon is grayscale; hover tints the icon; left-click toggles a popup and fetches status; right-click opens the Synergy app and brings its window forward.
- Icon setup (once):

```bash
mkdir -p ~/.config/sketchybar/icons
sips --matchTo \
"/System/Library/ColorSync/Profiles/Generic Gray Gamma 2.2 Profile.icc" \
~/.config/sketchybar/icons/synergy.png \
--out ~/.config/sketchybar/icons/synergy_gray.png
```

## Weather (`weather.lua`)

- Uses OpenWeather One Call API 3.0 for current conditions; shows condition, temperature, feels like, humidity, wind, pressure, time zone, sunrise, and sunset.
- Left-click toggles a centered popup titled with your location (`<place>` lat, lon) and a refresh affordance; click the title to refresh immediately; right-click opens the OpenWeather map for your coordinates (falls back to the macOS Weather app).
- Auto-refreshes hourly; coordinates come from the location helper (see `../../helpers/event_providers/location/README.md`) and are reverse-geocoded via OpenStreetMap.
- Setup: register an API key at https://openweathermap.org/api (free tier is 1,000 calls/day), then store it in Keychain:

```bash
security add-generic-password -a "$USER" -s OPENWEATHERMAP_API_KEY -w '<YOUR_API_KEY>' -U
```

The widget reads it with `security find-generic-password -a "$USER" -s OPENWEATHERMAP_API_KEY -w`. New keys can take 1-2 hours to activate.

## Now Playing (`now_playing.lua`)

- Displays track metadata (title, artist, album) for Apple Music, Spotify, and YouTube Music (via the browser bridge).
- See `../../helpers/event_providers/now_playing/README.md` for the Native Messaging bridge and installation steps.
