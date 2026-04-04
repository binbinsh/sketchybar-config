# sketchybar configuration

Lua-first SketchyBar setup for a consistent, customizable bar across displays (built on [SbarLua](https://github.com/FelixKratz/SbarLua)).

<img width="800" src="https://raw.githubusercontent.com/binbinsh/sketchybar-config/main/docs/screenshot.png">

## Quick start

Install the config (Homebrew required):

```bash
curl -fsSL https://raw.githubusercontent.com/binbinsh/sketchybar-config/main/bootstrap.sh | bash
```

The installer sets up SketchyBar, SbarLua, and the required fonts, including `Sarasa Term SC` and the latest `sketchybar-app-font`.
Window management is not installed by this repo. Use [binbinsh/rectangle](https://github.com/binbinsh/rectangle) separately and apply the recommended settings in `docs/rectangle.md`.

## Features

- Weather: Location-aware current conditions and a centered popup with 5-day outlook.
- Battery: Compact percentage + detailed popup (native helper).
- System stats: CPU/GPU/temperature and memory graphs via the native helper.
- Wi‑Fi: Throughput widget + details popup (native helpers).
- Pomodoro: Compact timer with click controls and persisted state.
- Spaces: Space switcher with persistent custom names.
- Volume: Compact volume + scroll to adjust.
- Menus: Apple menu + current app menu rendering driven by the native menus helper.
- 1Password: Quick Access launcher.
- Cloudflare WARP: Menubar menu shortcut with app-launch fallback.

## Docs

- Items and widgets: `docs/items.md`.
- Location helper: `docs/location.md`.
- Rectangle settings: `docs/rectangle.md`.
- System stats: `docs/system_stats.md`.
