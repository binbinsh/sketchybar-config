# Space Snapshot Scan

Helper to populate per-space app icons without yabai.

- [How it works](#how-it-works)
- [When it runs](#when-it-runs)
- [Build and manual run](#build-and-manual-run)
- [Limitations](#limitations)

## How it works

- Binary: `helpers/space_scan/bin/space_scan`
- Scans on-screen windows via CoreGraphics (layer 0), counts apps per owning process, determines the current Space via private SkyLight APIs, and emits a SketchyBar `space_snapshot` event with `space='<index>' apps='AppA:2|AppB:1|...'`.
- `items/spaces.lua` subscribes to `space_snapshot` and updates the corresponding `space.<index>` label immediately.

## When it runs

- Automatically on bar startup and on every `space_change` (wired in `items/spaces.lua`).

## Build and manual run

- Built automatically by `helpers/makefile` when SketchyBar starts.
- Manual run:

```bash
$CONFIG_DIR/helpers/space_scan/bin/space_scan
```

## Limitations

- Relies on private SkyLight APIs; behavior may change across macOS releases.
- Only scans the active Space; other Spaces stay "--" until you visit them (extend the helper if you need eager population).
