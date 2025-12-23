# SketchyBar Location Helper

Lightweight app to fetch current coordinates for the Weather widget.

- [What it does](#what-it-does)
- [Permissions](#permissions)
- [Troubleshooting](#troubleshooting)

## What it does

- App path: `helpers/location/bin/SketchyBarLocationHelper.app`.
- Invoked by `items/weather.lua` via `open -W ~/.config/sketchybar/helpers/location/bin/SketchyBarLocationHelper.app`.
- Build from root with `make -C helpers`, or from `helpers/location` with `make`; set `CODESIGN_ID` to your signing identity (defaults to ad-hoc `-`).
- Requests one-shot location, writes a cache line to `~/.cache/sketchybar/location.txt` as `ts|lat|lon|label`, then the widget reverse-geocodes and queries OpenWeather.

## Permissions

- First run shows the standard Location Services prompt for "SketchyBar Location Helper"; choose "While Using the App".
- Manage access under System Settings -> Privacy & Security -> Location Services.

## Troubleshooting

- If it times out (~15s) or the bar shows a LOC warning indicator, re-run the weather widget and ensure Location Services are enabled.
- Clear caches and retry if needed:

```bash
rm -f ~/.cache/sketchybar/location.txt ~/.cache/sketchybar/weather.txt
```
