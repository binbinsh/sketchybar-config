local colors = require("colors")
local settings = require("settings")

local durations = {
  focus = 25 * 60,
  short = 5 * 60,
  long = 15 * 60,
}
local cycle_total = 4

local phase = "focus"
local focus_completed = 0
local remaining = durations[phase]
local running = false
local last_tick = os.time()

local pomodoro = sbar.add("item", "pomodoro", {
  position = "right",
  icon = {
    string = "🍅",
    color = colors.red,
    padding_left = settings.paddings,
    padding_right = 4,
  },
  label = {
    string = "25:00 1/4",
    color = colors.red,
    padding_right = settings.paddings,
    font = { family = settings.font.numbers },
  },
  background = { drawing = false },
  update_freq = 1,
  updates = true,
})

sbar.add("bracket", "pomodoro.bracket", { pomodoro.name }, {
  background = { color = colors.bg1 },
})

sbar.add("item", "pomodoro.padding", {
  position = "right",
  width = settings.group_paddings,
})

local function format_time(seconds)
  local safe_seconds = math.max(seconds, 0)
  local minutes = math.floor(safe_seconds / 60)
  local secs = safe_seconds % 60
  return string.format("%02d:%02d", minutes, secs)
end

local function progress_text()
  if phase == "focus" then
    local current = (focus_completed % cycle_total) + 1
    return string.format("%d/%d", current, cycle_total)
  end

  local completed = focus_completed % cycle_total
  if completed == 0 then completed = cycle_total end
  return string.format("%d/%d", completed, cycle_total)
end

local function phase_color()
  if phase == "focus" then return colors.red end
  if phase == "short" then return colors.green end
  return colors.blue
end

local function phase_label(target)
  if target == "focus" then return "Focus" end
  if target == "short" then return "Short break" end
  return "Long break"
end

local function notify(message)
  local cmd = string.format(
    [[osascript -e 'display notification "%s" with title "Pomodoro" sound name "Glass"']],
    message
  )
  sbar.exec(cmd)
end

local function update_display()
  local tint = running and phase_color() or colors.grey
  pomodoro:set({
    icon = { color = tint },
    label = { string = format_time(remaining) .. " " .. progress_text(), color = tint },
  })
end

local function start_phase(next_phase)
  phase = next_phase
  remaining = durations[phase]
  last_tick = os.time()
  running = true

  update_display()
end

local function advance_phase()
  local previous_phase = phase
  local next_phase = "focus"
  if phase == "focus" then
    focus_completed = focus_completed + 1
    if focus_completed % cycle_total == 0 then
      next_phase = "long"
    else
      next_phase = "short"
    end
  end
  notify(string.format("%s ended, %s started", phase_label(previous_phase), phase_label(next_phase)))
  start_phase(next_phase)
end

local function toggle_running()
  running = not running
  if running then
    last_tick = os.time()
  end
  update_display()
end

local function reset_phase()
  remaining = durations[phase]
  last_tick = os.time()
  update_display()
end

pomodoro:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    reset_phase()
    return
  end
  if env.BUTTON ~= "left" then return end
  toggle_running()
end)

pomodoro:subscribe("routine", function()
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

update_display()
