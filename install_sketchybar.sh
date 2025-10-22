echo "Installing Dependencies"
# Packages
brew install lua

brew tap FelixKratz/formulae
brew install sketchybar

# Fonts
brew install --cask sf-symbols
brew install --cask font-sf-mono
brew install --cask font-sf-pro

curl -L https://github.com/kvndrsslr/sketchybar-app-font/releases/download/v2.0.47/sketchybar-app-font.ttf -o $HOME/Library/Fonts/sketchybar-app-font.ttf

# SbarLua
(git clone https://github.com/FelixKratz/SbarLua.git /tmp/SbarLua && cd /tmp/SbarLua/ && make install && rm -rf /tmp/SbarLua/)

# Install config from GitHub
echo "Installing SketchyBar config from GitHub"
TARGET_DIR="$HOME/.config/sketchybar"
REPO_URL="https://github.com/binbinsh/sketchybar-config.git"

if ! command -v git >/dev/null 2>&1; then
  brew install git
fi

if [ -d "$TARGET_DIR/.git" ]; then
  current_remote=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || echo "")
  if [ "$current_remote" != "$REPO_URL" ]; then
    echo "Backing up existing non-matching repo at $TARGET_DIR"
    mv "$TARGET_DIR" "${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
  else
    echo "Updating existing repo in $TARGET_DIR"
    default_branch=$(git -C "$TARGET_DIR" remote show origin | sed -n '/HEAD branch/s/.*: //p')
    git -C "$TARGET_DIR" fetch --prune origin
    git -C "$TARGET_DIR" checkout "$default_branch" >/dev/null 2>&1 || true
    git -C "$TARGET_DIR" reset --hard "origin/$default_branch"
  fi
elif [ -d "$TARGET_DIR" ]; then
  echo "Backing up existing non-git directory at $TARGET_DIR"
  mv "$TARGET_DIR" "${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
  git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
else
  git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
fi
brew services restart sketchybar

# For maximizing windows without yabai
brew install --cask hammerspoon

echo "Configuring Hammerspoon..."
mkdir -p "$HOME/.hammerspoon"
cat > "$HOME/.hammerspoon/init.lua" <<'EOF'
hs.window.animationDuration = 0

-- SketchyBar bar height from sketchybarrc
local TOP_PADDING = 32
local wf = hs.window.filter.new():setCurrentSpace(true)

-- Ensure windows don't cover the top bar by enforcing TOP_PADDING gap
local function clampTop(win)
  if not win or not win:isStandard() or win:isFullScreen() then return end
  local screen = win:screen()
  if not screen then return end
  local full = screen:fullFrame()
  local usable = screen:frame()
  local f = win:frame()
  if (f.y <= full.y + 1) or (f.y <= usable.y + 1) then
    local targetY = full.y + TOP_PADDING
    local targetH = math.min(f.h, full.h - TOP_PADDING)
    if math.abs(f.y - targetY) > 0.5 or math.abs(f.h - targetH) > 0.5 then
      f.y = targetY
      f.h = targetH
      win:setFrame(f, 0)
    end
  end
end

wf:subscribe({
  "windowMoved",
  "windowOnScreen",
}, function(win, appName, event)
  clampTop(win)
end, true)

-- Intercept apps' titlebar double-click to apply top-padding maximize
do
  local swallowNextUp = false
  local tap = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.leftMouseUp,
  }, function(ev)
    local et = ev:getType()
    if et == hs.eventtap.event.types.leftMouseDown then
      local clickState = ev:getProperty(hs.eventtap.event.properties.mouseEventClickState)
      if clickState == 2 then
        local win = hs.window.frontmostWindow()
        if not win then return false end
        local pos = hs.mouse.absolutePosition()
        local f = win:frame()
        local titlebarHeight = 60
        if pos.x >= f.x and pos.x <= f.x + f.w and pos.y >= f.y and pos.y <= f.y + titlebarHeight then
          local full = win:screen():fullFrame()
          win:setFrame({x = full.x, y = full.y + TOP_PADDING, w = full.w, h = full.h - TOP_PADDING}, 0)
          swallowNextUp = true
          return true
        end
      end
    elseif et == hs.eventtap.event.types.leftMouseUp then
      if swallowNextUp then
        swallowNextUp = false
        return true
      end
    end
    return false
  end)
  tap:start()
end

hs.hotkey.bind({"alt", "shift"}, "M", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  local full = win:screen():fullFrame()
  win:setFrame({x = full.x, y = full.y + TOP_PADDING, w = full.w, h = full.h - TOP_PADDING}, 0)
end)
EOF
