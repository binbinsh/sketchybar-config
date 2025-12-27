local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

-- Battery-style volume (compact bar item) + performance-first behavior:
-- - Click opens SoundSource (no popup)
-- - Right-click opens Sound settings
-- - Event-driven updates + scroll throttling

local function clamp_int(n, lo, hi)
  n = tonumber(n)
  if not n then return lo end
  if n < lo then return lo end
  if n > hi then return hi end
  return math.floor(n + 0.5)
end

local function icon_for_volume(volume)
  if volume > 60 then return icons.volume._100 end
  if volume > 30 then return icons.volume._66 end
  if volume > 10 then return icons.volume._33 end
  if volume > 0 then return icons.volume._10 end
  return icons.volume._0
end

local last_volume = nil
local last_icon = nil
local last_color = nil

local volume_item = sbar.add("item", "widgets.volume", {
  position = "right",
  icon = {
    string = icons.volume._100,
    color = colors.green,
    font = {
      style = settings.font.style_map["Regular"],
      size = 15.0,
    },
  },
  label = {
    string = "--",
    font = { family = settings.font.numbers },
    width = 32,
    padding_left = 2,
    padding_right = 6,
  },
  padding_left = 0,
  padding_right = 0,
})

volume_item:subscribe("volume_change", function(env)
  if _G.SKETCHYBAR_SUSPENDED then return end
  local v = clamp_int(env.INFO, 0, 100)
  local icon = icon_for_volume(v)
  local color = colors.green
  if last_volume == v and last_icon == icon and last_color == color then return end
  last_volume = v
  last_icon = icon
  last_color = color
  volume_item:set({ icon = { string = icon, color = color }, label = { string = tostring(v) } })
end)

local function open_soundsource()
  -- Prefer clicking the menu bar extra (fast, no focus steal).
  sbar.exec("$CONFIG_DIR/helpers/menus/bin/menus -s SoundSource >/dev/null 2>&1", function(_, exit_code)
    if exit_code == 0 then return end
    -- If SoundSource isn't running, launch it and retry once.
    sbar.exec('/usr/bin/open -gja "SoundSource" >/dev/null 2>&1', function() end)
    sbar.delay(0.1, function()
      sbar.exec("$CONFIG_DIR/helpers/menus/bin/menus -s SoundSource >/dev/null 2>&1", function() end)
    end)
  end)
end

local scroll_pending = 0
local scroll_armed = false
local function volume_scroll(env)
  if _G.SKETCHYBAR_SUSPENDED then return end
  local info = env and env.INFO or {}
  local delta = tonumber(info.delta) or 0
  if delta == 0 then return end
  if info.modifier ~= "ctrl" then
    delta = delta * 10
  end

  -- Coalesce high-frequency scroll events to avoid spawning many osascript processes.
  scroll_pending = scroll_pending + delta
  if scroll_armed then return end
  scroll_armed = true

  sbar.delay(0.08, function()
    scroll_armed = false
    local pending = tonumber(scroll_pending) or 0
    scroll_pending = 0
    if pending == 0 then return end
    sbar.exec('osascript -e "set volume output volume (output volume of (get volume settings) + ' .. tostring(pending) .. ')"')
  end)
end

volume_item:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("/usr/bin/open 'x-apple.systempreferences:com.apple.preference.sound' >/dev/null 2>&1", function() end)
    return
  end
  if env.BUTTON ~= "left" then return end
  open_soundsource()
end)
volume_item:subscribe("mouse.scrolled", volume_scroll)

-- Initial sync (best effort).
sbar.exec([[osascript -e 'output volume of (get volume settings)']], function(out, exit_code)
  if exit_code ~= 0 then return end
  local v = tonumber(tostring(out or ""):match("(%d+)"))
  if not v then return end
  local vv = clamp_int(v, 0, 100)
  local icon = icon_for_volume(vv)
  local color = colors.green
  last_volume = vv
  last_icon = icon
  last_color = color
  volume_item:set({ icon = { string = icon, color = color }, label = { string = tostring(vv) } })
end)
