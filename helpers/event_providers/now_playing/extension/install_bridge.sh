#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./install_bridge.sh --ext-id=<EXTENSION_ID>
#
# Notes:
# - --ext-id is the extension ID shown in chrome://extensions (Developer mode).
#
EXT_ID=""
for arg in "$@"; do
  case "$arg" in
    --ext-id=*) EXT_ID="${arg#*=}" ;;
    *) echo "Unknown arg: $arg" && exit 1 ;;
  esac
done

if [[ -z "$EXT_ID" ]]; then
  echo "Usage: $0 --ext-id=<EXTENSION_ID>"
  exit 1
fi

# On macOS, both Brave and Chrome honor a host manifest placed under the
# Chrome profile path. We therefore always install to the Chrome path for
# consistency between browsers.
PROFILE_DIR="$HOME/Library/Application Support/Google/Chrome"

HOSTS_DIR="$PROFILE_DIR/NativeMessagingHosts"
mkdir -p "$HOSTS_DIR"

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_JSON_TEMPLATE="$TEMPLATE_DIR/native_host.json"
TARGET_JSON="$HOSTS_DIR/com.sketchybar.nowplaying.json"

NOW_PLAYING_BIN="$HOME/.config/sketchybar/helpers/event_providers/now_playing/bin/now_playing"

if [[ ! -x "$NOW_PLAYING_BIN" ]]; then
  echo "Building now_playing binary..."
  (cd "$HOME/.config/sketchybar/helpers" && make >/dev/null)
fi

echo "Installing native messaging host to: $TARGET_JSON"
sed -e "s|/Users/USERNAME/.config/sketchybar/helpers/event_providers/now_playing/bin/now_playing|$NOW_PLAYING_BIN|g" \
    -e "s|REPLACE_WITH_EXTENSION_ID|$EXT_ID|g" \
    "$HOST_JSON_TEMPLATE" > "$TARGET_JSON"

echo "Done. Restart your browser (Chrome/Brave) and ensure the extension is loaded."


