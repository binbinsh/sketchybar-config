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

-- Global variable to keep the event tap alive
local doubleclickTap = nil

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

-- Hotkey for manual maximize with padding
hs.hotkey.bind({"alt", "shift"}, "M", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  local full = win:screen():fullFrame()
  win:setFrame({x = full.x, y = full.y + TOP_PADDING, w = full.w, h = full.h - TOP_PADDING}, 0)
  print("Alt+Shift+M: Window maximized with padding")
end)

-- Function to create/recreate the event tap
local function createDoubleclickTap()
  local lastClickTime = 0
  local lastClickPos = {x = 0, y = 0}
  
  -- Stop existing tap if it exists
  if doubleclickTap then
    doubleclickTap:stop()
    doubleclickTap = nil
  end
  
  doubleclickTap = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDown,
  }, function(ev)
    local clickState = ev:getProperty(hs.eventtap.event.properties.mouseEventClickState)
    local pos = hs.mouse.absolutePosition()
    local currentTime = hs.timer.secondsSinceEpoch()
    
    -- First, handle manual double-click detection
    if clickState == 1 then
      -- Single click
      local timeDiff = currentTime - lastClickTime
      local posDiff = math.sqrt((pos.x - lastClickPos.x)^2 + (pos.y - lastClickPos.y)^2)
      
      if timeDiff < 0.5 and posDiff < 5 then
        -- This is a double-click
        local win = hs.window.frontmostWindow()
        if win then
          local f = win:frame()
          -- Check if click is in titlebar area (be generous with the area)
          if pos.y >= f.y and pos.y <= f.y + 50 and 
             pos.x >= f.x and pos.x <= f.x + f.w then
            print("Manual double-click detected in titlebar")
            -- Use a timer to ensure the key event is processed after the click
            hs.timer.doAfter(0.05, function()
              hs.eventtap.keyStroke({"alt", "shift"}, "M", 0)
            end)
            lastClickTime = 0 -- Reset to prevent triple-click
            return true -- Block the event
          end
        end
      end
      
      lastClickTime = currentTime
      lastClickPos = pos
    elseif clickState == 2 then
      -- System detected double-click
      local win = hs.window.frontmostWindow()
      if win then
        local f = win:frame()
        -- Check if click is in titlebar area
        if pos.y >= f.y and pos.y <= f.y + 50 and 
           pos.x >= f.x and pos.x <= f.x + f.w then
          print("System double-click detected in titlebar")
          -- Use a timer to ensure the key event is processed
          hs.timer.doAfter(0.05, function()
            hs.eventtap.keyStroke({"alt", "shift"}, "M", 0)
          end)
          return true -- Block the event
        end
      end
    end
    
    return false
  end)
  
  doubleclickTap:start()
  print("Hammerspoon: Event tap created/recreated")
end

-- Create the initial tap
createDoubleclickTap()

-- Monitor the tap and restart if needed
tapMonitor = hs.timer.doEvery(30, function()
  if not doubleclickTap or not doubleclickTap:isEnabled() then
    print("Event tap was disabled, restarting...")
    createDoubleclickTap()
  end
end)

-- Also recreate tap when system wakes from sleep
wakeWatcher = hs.caffeinate.watcher.new(function(eventType)
  if eventType == hs.caffeinate.watcher.systemDidWake then
    print("System woke from sleep, recreating event tap...")
    hs.timer.doAfter(1, createDoubleclickTap)
  end
end)
wakeWatcher:start()

print("Hammerspoon: Titlebar double-click interception enabled with auto-recovery")
EOF
