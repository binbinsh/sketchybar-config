hs.window.animationDuration = 0

-- SketchyBar bar height from sketchybarrc
local TOP_PADDING = 32
local TITLEBAR_ZONE = 36 -- pixels from the top edge we treat as titlebar for double-click
local wf = hs.window.filter.new():setCurrentSpace(true)
local ax = hs.axuielement

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

  local interactiveRoles = {
    AXTextField = true,
    AXTextArea = true,
    AXWebArea = true,
    AXButton = true,
    AXPopUpButton = true,
    AXComboBox = true,
    AXTab = true,
  }

  local interactiveSubroles = {
    AXSearchField = true,
  }

  local function isTitlebarClick(win, pos)
    if not win then return false end
    local f = win:frame()
    if pos.y < f.y or pos.y > f.y + TITLEBAR_ZONE or pos.x < f.x or pos.x > f.x + f.w then
      return false
    end

    -- Ignore clicks on interactive controls (e.g. address bar) even if they are near the top
    local ok, elem = pcall(function()
      return ax.systemWideElement():elementAtPosition(pos)
    end)
    if ok and elem then
      local role = elem:attributeValue("AXRole")
      local subrole = elem:attributeValue("AXSubrole")
      if (role and interactiveRoles[role]) or (subrole and interactiveSubroles[subrole]) then
        return false
      end
    end

    return true
  end

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
          if isTitlebarClick(win, pos) then
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
        if isTitlebarClick(win, pos) then
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
