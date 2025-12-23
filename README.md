# sketchybar configuration

Lua-first SketchyBar setup for a consistent, customizable bar across displays (built on [SbarLua](https://github.com/FelixKratz/SbarLua)).

<img width="800" src="https://raw.githubusercontent.com/binbinsh/sketchybar-config/main/docs/screenshot.png">

## Quick start

Install the config (Homebrew required):

```bash
curl -L https://raw.githubusercontent.com/binbinsh/sketchybar-config/main/install_sketchybar.sh | sh
```

## Features

- Weather: Location-aware current conditions and detailed popup with refresh controls.
- System stats: CPU/GPU/temperature and memory metrics via the native helper.
- GitHub: Issue/PR/repo counts plus a new-issue badge.
- Pomodoro: Minimal focus timer with click controls and notifications.
- WeChat: Unread badge display with click-to-open behavior.
- Ubuntu monitor: Remote CPU/GPU/memory/load metrics over SSH.

## Docs

- Items and widgets: `docs/items.md`.
- Location helper: `docs/location.md`.
- Space scan helper: `docs/space_scan.md`.
- System stats: `docs/system_stats.md`.
