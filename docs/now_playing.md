# Now Playing Event Provider

Helper binary bridging browser media playback and Apple Music control to SketchyBar.

- [Overview](#overview)
- [Modes](#modes)
- [Install the YouTube Music bridge](#install-the-youtube-music-bridge)
- [Permissions and troubleshooting](#permissions-and-troubleshooting)

## Overview

- Binary: `helpers/now_playing/bin/now_playing`
- Purpose: emit `media_nowplaying` events carrying track metadata for the bar and provide transport controls.

## Modes

- **Native Messaging**: invoked by the browser extension; receives title/artist/album/state/elapsed/duration and fires the `media_nowplaying` SketchyBar event.
- **Standalone**: when run with `previous|next|toggle|playpause`, first tries to control YouTube Music tabs in Chrome/Brave (injecting JS for media actions) and falls back to Apple Music via AppleScript.

## Install the YouTube Music bridge

1. In Chrome/Brave open `chrome://extensions`, enable Developer Mode, click "Load unpacked", and select `helpers/now_playing/extension/`.
2. Copy the Extension ID shown on the card.
3. Install the native messaging host:

```bash
helpers/now_playing/extension/install_bridge.sh --ext-id <EXTENSION_ID>
```

This writes `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.sketchybar.nowplaying.json` pointing to `~/.config/sketchybar/helpers/now_playing/bin/now_playing` and whitelists your extension ID.

4. Restart the browser (`chrome://restart` or `brave://restart`), then play/pause on https://music.youtube.com to confirm events arrive.

## Permissions and troubleshooting

- Native messaging requires no extra permissions; Apple Music control needs the Music app accessible via AppleScript.
- If the extension cannot connect, confirm the native host manifest exists (step 3) and check the extension's Service Worker console for errors.
- Ensure the binary is executable: `chmod +x ~/.config/sketchybar/helpers/now_playing/bin/now_playing`.
