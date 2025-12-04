# sketchybar configuration

Lua-first SketchyBar setup for a consistent, customizable bar across displays (built on [SbarLua](https://github.com/FelixKratz/SbarLua)).

<img width="800" src="https://raw.githubusercontent.com/binbinsh/sketchybar-config/main/screenshot.png">

## Quick start

Install the config (Homebrew required):

```bash
curl -L https://raw.githubusercontent.com/binbinsh/sketchybar-config/main/install_sketchybar.sh | sh
```

## Highlights

Items overview: [items/README.md](items/README.md); Widgets: [items/widgets/README.md](items/widgets/README.md).

Space scan helper shows per-space app icons without yabai ([helpers/event_providers/space_scan/README.md](helpers/event_providers/space_scan/README.md)).

Weather widget auto-fetches coordinates via the bundled Location Helper and uses OpenWeather One Call API 3.0 (free API key needed from https://openweathermap.org/api) ([helpers/event_providers/location/README.md](helpers/event_providers/location/README.md)).

Now Playing covers Apple Music, Spotify, and YouTube Music via the browser bridge ([helpers/event_providers/now_playing/README.md](helpers/event_providers/now_playing/README.md)).
