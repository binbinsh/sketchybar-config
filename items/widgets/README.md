# Widgets & Integrations

Quick reference for the app integrations and interactive widgets in this directory.

- [Shortcuts](#shortcuts-shortcutslua)
- [Volume](#volume-volumelua)
- [iStat Menus](#istat-menus-istat_menuslua)
- [Weather](#weather-weatherlua)
- [Now Playing](#now-playing-now_playinglua)

## Shortcuts (`shortcuts.lua`)

- A row of shortcut icons (Clipboard, Dictionary, LM Studio, 1Password, Quantumult X, Synergy, Time Machine, Ubuntu, WeChat) managed in one widget file.
- Left-click each icon to open its own centered popup; right-click does nothing.

## Volume (`volume.lua`)

- Shows the current output volume and an icon.
- Click opens SoundSource; right-click opens Sound settings.

## iStat Menus (`istat_menus.lua`)

- Automatically aliases the Combined menu extra when available and groups it; click opens Activity Monitor.
- Setup: enable the Combined menu extra in iStat Menus so it can be aliased.

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
