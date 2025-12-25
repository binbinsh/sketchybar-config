# sketchybar configuration

Lua-first SketchyBar setup for a consistent, customizable bar across displays (built on [SbarLua](https://github.com/FelixKratz/SbarLua)).

<img width="800" src="https://raw.githubusercontent.com/binbinsh/sketchybar-config/main/docs/screenshot.png">

## Quick start

Install the config (Homebrew required):

```bash
curl -L https://raw.githubusercontent.com/binbinsh/sketchybar-config/main/install_sketchybar.sh | sh
```

## Features

- Weather: Location-aware current conditions and a centered popup with refresh controls.
- System stats: CPU/GPU/temperature and memory graphs via the native helper.
- Battery: Compact percentage + detailed popup (native helper).
- Wi‑Fi: Throughput widget + details popup (native helpers).
- Menus: Apple menu + current app menu rendering driven by the native menus helper.
- Pomodoro: Compact timer with click controls and persisted state.
- Spaces: Space switcher with persistent custom names.
- Volume: Compact volume + scroll to adjust; integrates with SoundSource when available.
- 1Password: Quick Access launcher.

## Docs

- Items and widgets: `docs/items.md`.
- Location helper: `docs/location.md`.
- System stats: `docs/system_stats.md`.
