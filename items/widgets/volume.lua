local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

local popup_width = 250

local volume_percent = sbar.add("item", "widgets.volume1", {
  position = "right",
  icon = { drawing = false },
  label = {
    string = "??%",
    padding_left = -1,
    font = { family = settings.font.numbers }
  },
})

local volume_icon = sbar.add("item", "widgets.volume2", {
  position = "right",
  padding_right = -1,
  icon = {
    string = icons.volume._100,
    width = 0,
    align = "left",
    color = colors.grey,
    font = {
      style = settings.font.style_map["Regular"],
      size = 14.0,
    },
  },
  label = {
    width = 25,
    align = "left",
    font = {
      style = settings.font.style_map["Regular"],
      size = 14.0,
    },
  },
})

local volume_bracket = sbar.add("bracket", "widgets.volume.bracket", {
  volume_icon.name,
  volume_percent.name
}, {
  background = { color = colors.bg1 },
  popup = { align = "center" }
})

sbar.add("item", "widgets.volume.padding", {
  position = "right",
  width = settings.group_paddings
})

local volume_slider = sbar.add("slider", popup_width, {
  position = "popup." .. volume_bracket.name,
  slider = {
    highlight_color = colors.blue,
    background = {
      height = 6,
      corner_radius = 3,
      color = colors.bg2,
    },
    knob= {
      string = "􀀁",
      drawing = true,
    },
  },
  background = { color = colors.bg1, height = 2, y_offset = -20 },
  click_script = 'osascript -e "set volume output volume $PERCENTAGE"'
})

volume_percent:subscribe("volume_change", function(env)
  local volume = tonumber(env.INFO)
  local icon = icons.volume._0
  if volume > 60 then
    icon = icons.volume._100
  elseif volume > 30 then
    icon = icons.volume._66
  elseif volume > 10 then
    icon = icons.volume._33
  elseif volume > 0 then
    icon = icons.volume._10
  end

  local lead = ""
  if volume < 10 then
    lead = "0"
  end

  volume_icon:set({ label = icon })
  volume_percent:set({ label = lead .. volume .. "%" })
  volume_slider:set({ slider = { percentage = volume } })
end)

local function volume_collapse_details()
  local drawing = volume_bracket:query().popup.drawing == "on"
  if not drawing then return end
  volume_bracket:set({ popup = { drawing = false } })
  sbar.remove('/volume.device\\.*/')
end

local function volume_toggle_details(env)
  if env.BUTTON == "right" then
    sbar.exec("open /System/Library/PreferencePanes/Sound.prefpane")
    return
  end

  -- Open SoundSource menubar popover similar to backup script
  sbar.exec([[osascript <<'APPLESCRIPT' >/dev/null 2>&1
tell application "System Events"
  if not (exists process "SoundSource") then
    tell application "SoundSource" to launch
    delay 0.4
  end if
  tell application process "SoundSource"
    click menu bar item 1 of menu bar 2
    delay 0.08
    if (exists window 1) then
      set p to position of window 1
      set x to item 1 of p
      set y to item 2 of p
      set position of window 1 to {x, y + 32}
    end if
  end tell
end tell
APPLESCRIPT
]])
end

local function volume_scroll(env)
  local delta = env.INFO.delta
  if not (env.INFO.modifier == "ctrl") then delta = delta * 10.0 end

  sbar.exec('osascript -e "set volume output volume (output volume of (get volume settings) + ' .. delta .. ')"')
end

volume_icon:subscribe("mouse.clicked", volume_toggle_details)
volume_icon:subscribe("mouse.scrolled", volume_scroll)
volume_percent:subscribe("mouse.clicked", volume_toggle_details)
volume_percent:subscribe("mouse.exited.global", volume_collapse_details)
volume_percent:subscribe("mouse.scrolled", volume_scroll)

