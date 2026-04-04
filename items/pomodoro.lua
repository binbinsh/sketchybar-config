local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

-- Pomodoro timer focused on two phases only: Focus and Rest.
-- - Stacked labels in the bar: top = "FOCUS" / "REST", bottom = remaining time.
-- - Left click toggles running state.
-- - Right click opens a centered popup for duration adjustments.

local durations = {
  focus = 25 * 60,
  rest = 5 * 60,
}
local phase = "focus"
local remaining = durations[phase]
local running = false
local last_tick = os.time()
local state_dir = os.getenv("HOME") .. "/.config/sketchybar/states"
local state_path = state_dir .. "/pomodoro_state.lua"
local last_saved_at = 0

-- UI cache to avoid unnecessary redraws.
local last_ui_top = nil
local last_ui_bottom = nil
local last_ui_top_color = nil
local last_ui_bottom_color = nil
local last_ui_freq = nil

local duration_bounds = {
  focus = { min = 0, max = 120 },
  rest = { min = 0, max = 30 },
}

-- Performance
local RUN_TICK = 1
local IDLE_TICK = 300

local line_width = 44
local line_font = {
  family = settings.font.numbers,
  style = settings.font.style_map["Bold"],
  size = 9.0,
}

local function ensure_state_dir()
  os.execute('mkdir -p "' .. state_dir .. '"')
end

local function minutes_from_percentage(pct, kind)
  local value = duration_bounds[kind].min + (pct / 100) * (duration_bounds[kind].max - duration_bounds[kind].min)
  return math.max(duration_bounds[kind].min, math.min(duration_bounds[kind].max, math.floor(value + 0.5)))
end

local function percentage_from_minutes(minutes, kind)
  local min = duration_bounds[kind].min
  local max = duration_bounds[kind].max
  return math.max(0, math.min(100, math.floor(((minutes - min) / (max - min)) * 100 + 0.5)))
end

local function save_pomodoro_state()
  ensure_state_dir()
  local file = io.open(state_path, "w")
  if not file then return end

  local focus_minutes = math.max(1, math.floor(durations.focus / 60))
  local rest_minutes = math.max(1, math.floor(durations.rest / 60))
  local rem = math.max(0, math.floor(remaining or durations[phase] or 0))

  local lines = {
    "return {",
    "  config = {",
    string.format("    focus = %d,", focus_minutes),
    string.format("    rest = %d,", rest_minutes),
    "  },",
    "  state = {",
    string.format("    phase = %q,", tostring(phase)),
    string.format("    remaining = %d,", rem),
    string.format("    running = %s,", running and "true" or "false"),
    "  },",
    "}",
  }

  file:write(table.concat(lines, "\n"))
  file:write("\n")
  file:close()
end

local function save_state_throttled(force)
  local now = os.time()
  if force or (now - last_saved_at) >= 60 then
    save_pomodoro_state()
    last_saved_at = now
  end
end

local function load_pomodoro_state()
  local chunk = loadfile(state_path, "t", {})
  if not chunk then return end

  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return end

  local config = type(data.config) == "table" and data.config or nil
  if config then
    local focus_minutes = tonumber(config.focus)
    local rest_minutes = tonumber(config.rest)
    if focus_minutes and focus_minutes > 0 then
      durations.focus = math.floor(focus_minutes) * 60
    end
    if rest_minutes and rest_minutes > 0 then
      durations.rest = math.floor(rest_minutes) * 60
    end
  end

  local state = type(data.state) == "table" and data.state or nil
  if state then
    local loaded_phase = state.phase
    if loaded_phase == "focus" or loaded_phase == "rest" then
      phase = loaded_phase
    end

    local loaded_remaining = tonumber(state.remaining)
    if loaded_remaining then
      remaining = math.min(math.max(math.floor(loaded_remaining), 0), durations[phase])
    else
      remaining = durations[phase]
    end

    running = state.running == true
  else
    remaining = durations[phase]
  end

  if remaining <= 0 then
    remaining = durations[phase]
  end

  last_tick = os.time()
end

local function format_time(seconds)
  local safe_seconds = math.max(seconds, 0)
  local minutes = math.floor(safe_seconds / 60)
  local secs = safe_seconds % 60
  return string.format("%02d:%02d", minutes, secs)
end

local function phase_label()
  if phase == "focus" then return "FOCUS" end
  return "REST"
end

local function phase_color()
  if phase == "focus" then return colors.green end
  return colors.green
end

local function notify(message)
  local safe = tostring(message):gsub("\\", "\\\\"):gsub('"', '\\"')
  local cmd = string.format([[osascript -e 'display notification "%s" with title "Pomodoro" sound name "Glass"']], safe)
  sbar.exec(cmd)
end

local function update_durations_for_phase()
  if phase == "focus" then
    remaining = durations.focus
  else
    remaining = durations.rest
  end
end

-- Stacked bar items for compact display.
local pomodoro_top = sbar.add("item", "pomodoro.top", {
  position = "right",
  width = 0,
  padding_left = 0,
  padding_right = 0,
  icon = { drawing = false },
  label = {
    font = line_font,
    width = line_width,
    padding_left = 2,
    padding_right = 4,
    align = "left",
    color = colors.red,
    string = "FOCUS",
  },
  y_offset = 5,
  background = { drawing = false },
})

local pomodoro_bottom = sbar.add("item", "pomodoro.bottom", {
  position = "right",
  padding_left = 0,
  padding_right = 0,
  icon = { drawing = false },
  label = {
    font = line_font,
    width = line_width,
    padding_left = 2,
    padding_right = 4,
    align = "left",
    color = colors.green,
    string = "25:00",
  },
  y_offset = -5,
  background = { drawing = false },
})

local pomodoro = sbar.add("item", "pomodoro", {
  position = "right",
  icon = {
    string = "🍅",
    font = {
      style = settings.font.style_map["Regular"],
      size = 15.0,
    },
    padding_right = settings.icon_paddings,
    y_offset = 1,
  },
  label = { drawing = false },
  padding_left = 0,
  padding_right = 0,
  update_freq = IDLE_TICK,
  background = { drawing = false },
})

-- Popup setup (reference: volume widget popup behavior).
local popup_width = 380
local pomodoro_popup = center_popup.create("pomodoro.popup", {
  width = popup_width,
  popup_height = 26,
  title = "Pomodoro",
  meta = "",
  auto_hide = false,
})
pomodoro_popup.meta_item:set({ drawing = false })
pomodoro_popup.body_item:set({ drawing = false })
pomodoro_popup.position = pomodoro_popup.position or "right"
local popup_pos = pomodoro_popup.position
local name_width = 130
local value_width = popup_width - name_width

local function add_row(key, title, opts)
  opts = opts or {}
  return sbar.add("item", "pomodoro.popup." .. key, {
    position = popup_pos,
    width = popup_width,
    drawing = opts.drawing,
    icon = {
      align = "left",
      string = title,
      width = name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 12.0 },
    },
    label = {
      align = "right",
      string = "-",
      width = value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 12.0 },
      max_chars = 48,
    },
    background = { drawing = false },
  })
end

local row_focus = add_row("focus", "Focus interval")
local focus_slider = pomodoro_popup.add_slider("focus", {
  highlight_color = colors.green,
  percentage = 0,
})

local row_rest = add_row("rest", "Rest interval")
local rest_slider = pomodoro_popup.add_slider("rest", {
  highlight_color = colors.green,
  percentage = 0,
})

pomodoro_popup.add_close_row({ label = "close x" })

local function update_popup_display()
  local focus_minutes = math.floor(durations.focus / 60)
  local rest_minutes = math.floor(durations.rest / 60)

  focus_slider:set({ slider = { percentage = percentage_from_minutes(focus_minutes, "focus") } })
  rest_slider:set({ slider = { percentage = percentage_from_minutes(rest_minutes, "rest") } })
  row_focus:set({ label = { string = string.format("%d min (0-120)", focus_minutes) } })
  row_rest:set({ label = { string = string.format("%d min (0-30)", rest_minutes) } })
end

local update_display

local function set_duration(kind, minutes)
  local bounds = duration_bounds[kind]
  if not bounds then return end
  local clamped = math.max(bounds.min, math.min(bounds.max, math.floor(minutes)))
  durations[kind] = clamped * 60

  if phase == kind then
    update_durations_for_phase()
    last_tick = os.time()
    if not running then
      update_display()
    end
  end
end

local function scroll_delta_from_env(env)
  local raw = nil
  if env and env.INFO then
    raw = env.INFO.delta or env.INFO.scroll_delta or env.INFO.DELTA
  end
  if raw == nil then
    raw = env and (env.delta or env.DELTA)
  end
  return tonumber(raw) or 0
end

local function apply_slider_scroll(kind, env)
  local delta = scroll_delta_from_env(env)
  if delta == 0 then return end
  local bounds = duration_bounds[kind]
  if not bounds then return end

  local current = math.floor((durations[kind] or 0) / 60)
  if delta > 0 then
    current = current + 1
  else
    current = current - 1
  end
  set_duration(kind, current)
  update_popup_display()
  update_display()
  save_state_throttled(true)
end

local function apply_slider_change(kind)
  return function(env)
    local pct = tonumber(env.PERCENTAGE)
    if not pct then return end
    set_duration(kind, minutes_from_percentage(pct, kind))
    update_popup_display()
    update_display()
    save_state_throttled(true)
  end
end

focus_slider:subscribe("mouse.clicked", apply_slider_change("focus"))
rest_slider:subscribe("mouse.clicked", apply_slider_change("rest"))
focus_slider:subscribe("mouse.scrolled", function(env)
  apply_slider_scroll("focus", env)
end)
rest_slider:subscribe("mouse.scrolled", function(env)
  apply_slider_scroll("rest", env)
end)
row_focus:subscribe("mouse.scrolled", function(env)
  apply_slider_scroll("focus", env)
end)
row_rest:subscribe("mouse.scrolled", function(env)
  apply_slider_scroll("rest", env)
end)

update_display = function()
  local top = phase_label()
  local bottom = format_time(remaining)
  local freq = running and RUN_TICK or IDLE_TICK
  local top_color = phase_color()
  local bottom_color = running and colors.white or colors.grey

  local props = nil
  if last_ui_freq ~= freq then
    props = props or {}
    props.update_freq = freq
    last_ui_freq = freq
  end

  if props then
    pomodoro:set(props)
  end

  if last_ui_top ~= top or last_ui_top_color ~= top_color then
    pomodoro_top:set({
      label = {
        string = top,
        color = top_color,
      },
    })
    last_ui_top = top
    last_ui_top_color = top_color
  end

  if last_ui_bottom ~= bottom or last_ui_bottom_color ~= bottom_color then
    pomodoro_bottom:set({
      label = {
        string = bottom,
        color = bottom_color,
      },
    })
    last_ui_bottom = bottom
    last_ui_bottom_color = bottom_color
  end

  if running then
    save_state_throttled(false)
  end
end

local function start_phase(next_phase)
  phase = next_phase
  update_durations_for_phase()
  last_tick = os.time()
  running = true
  update_display()
  save_state_throttled(true)
end

local function advance_phase()
  local next_phase = "focus"
  if phase == "focus" then
    next_phase = "rest"
  end
  notify(string.format("%s ended, %s started", phase_label(), phase_label() == "FOCUS" and "REST" or "FOCUS"))
  start_phase(next_phase)
end

local function toggle_running()
  running = not running
  if running then
    last_tick = os.time()
  end
  update_display()
  save_state_throttled(true)
end

local function reset_phase()
  update_durations_for_phase()
  last_tick = os.time()
  update_display()
  save_state_throttled(true)
end

local function pomodoro_on_click(env)
  if env.BUTTON == "right" then
    if pomodoro_popup.is_showing() then
      pomodoro_popup.hide()
      return
    end

    update_popup_display()
    pomodoro_popup.show(function()
      update_popup_display()
    end)
    return
  end

  if env.BUTTON == "middle" or env.BUTTON == "other" then
    reset_phase()
    return
  end

  if env.BUTTON == "left" then
    toggle_running()
  end
end

pomodoro:subscribe("mouse.clicked", pomodoro_on_click)
pomodoro_top:subscribe("mouse.clicked", pomodoro_on_click)
pomodoro_bottom:subscribe("mouse.clicked", pomodoro_on_click)

pomodoro:subscribe("routine", function()
  if _G.SKETCHYBAR_SUSPENDED then return end
  if running then
    local now = os.time()
    local elapsed = now - last_tick
    if elapsed > 0 then
      remaining = remaining - elapsed
      last_tick = now
    end
    if remaining <= 0 then
      advance_phase()
      return
    end
  end
  update_display()
end)

load_pomodoro_state()
update_popup_display()
update_display()

pomodoro:subscribe("system_woke", function(_)
  if _G.SKETCHYBAR_SUSPENDED then return end
  if running then
    local now = os.time()
    local elapsed = now - last_tick
    if elapsed > 0 then
      remaining = remaining - elapsed
      last_tick = now
    end
    if remaining <= 0 then
      advance_phase()
      return
    end
  end
  update_display()
end)
