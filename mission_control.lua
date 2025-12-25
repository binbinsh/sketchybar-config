-- Mission Control performance guard
--
-- Mission Control is owned by Dock and can spam events and increase both
-- WindowServer and SketchyBar CPU usage. This module detects when Dock becomes
-- the front app and temporarily disables bar drawing. It also exposes a global
-- flag so other items can skip heavy updates while Mission Control is active.

_G.SKETCHYBAR_SUSPENDED = _G.SKETCHYBAR_SUSPENDED or false

local watcher = sbar.add("item", "perf.mission_control", {
  drawing = false,
  updates = true,
})

-- Always start in a non-suspended state to avoid getting "stuck hidden" if a
-- previous run crashed while suspended.
_G.SKETCHYBAR_SUSPENDED = false
local last_suspended = false

-- Ensure the bar is visible on load (bar "hidden" state persists across reloads).
sbar.bar({ hidden = "off", drawing = "on" })

local suspend_token = 0
local timer_armed = false
local requested_delay = 0.0

local function apply_state(suspended)
  if suspended == last_suspended then return end
  last_suspended = suspended
  _G.SKETCHYBAR_SUSPENDED = suspended

  -- Keep the bar visible; only expose a global suspended flag so items can skip
  -- expensive updates during Mission Control / Space transitions.
  if not suspended then
    sbar.bar({ hidden = "off", drawing = "on" })
  end
end

local function arm_timer()
  if timer_armed then return end
  timer_armed = true

  local token_at_schedule = suspend_token
  local delay = requested_delay
  if delay <= 0.0 then delay = 0.25 end
  requested_delay = 0.0

  sbar.delay(delay, function()
    timer_armed = false
    if token_at_schedule ~= suspend_token then
      -- More suspend requests happened while the timer was running; arm again.
      arm_timer()
      return
    end
    apply_state(false)
  end)
end

local function suspend_for(seconds)
  local delay = tonumber(seconds) or 0.0
  if delay <= 0.0 then return end
  suspend_token = suspend_token + 1
  if delay > requested_delay then requested_delay = delay end
  apply_state(true)
  arm_timer()
end

-- Space transitions (trackpad swipe / Mission Control) are the biggest source of
-- WindowServer spikes. Hide the bar briefly during the animation.
watcher:subscribe("space_change", function(_)
  suspend_for(0.35)
end)

-- If Mission Control does switch focus to Dock on your macOS version, keep the
-- bar hidden while Dock stays active (debounced).
local last_app = ""
watcher:subscribe("front_app_switched", function(env)
  local app = (env and env.INFO) or ""
  if app == "" or app == last_app then return end
  last_app = app
  if app == "Dock" then
    suspend_for(1.0)
  end
end)


