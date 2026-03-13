local colors = require("colors")
local settings = require("settings")

local menu_watcher = sbar.add("item", "menus.watcher", {
  drawing = false,
  updates = true,
})

local SWITCH_DEBOUNCE_S = 0.45

-- Visual tuning (purely cosmetic)
local MENU_ITEM_GAP = 2         -- spacing between items
local MENU_LABEL_PADDING = 6    -- inner padding for each label

local max_items = 15
local menu_items = {}
for i = 1, max_items, 1 do
  local menu = sbar.add("item", "menu." .. i, {
    -- Battery-style compact spacing (keep behavior identical; only visuals).
    padding_left = MENU_ITEM_GAP,
    padding_right = MENU_ITEM_GAP,
    drawing = false,
    icon = { drawing = false, width = 0 },
    label = {
      font = {
        family = settings.font.text,
        size = 14.0,
      },
      padding_left = MENU_LABEL_PADDING,
      padding_right = MENU_LABEL_PADDING,
    },
    background = { drawing = false },
    click_script = "$CONFIG_DIR/helpers/menus/bin/menus -s " .. i,
  })

  menu_items[i] = menu
end

-- A more opaque background to visually mask the native macOS app menu text.
-- Keep the same pill geometry as the global default (height/corner/border).
sbar.add("bracket", "menus.bracket", { '/menu\\..*/' }, {
  background = {
    drawing = false,
  },
})

local menu_padding = sbar.add("item", "menu.padding", {
  drawing = false,
  width = settings.group_paddings,
})

-- App-switch robustness:
-- The menus helper reads the *current* front process. During app transitions
-- (and especially with heavier apps like Electron), the native menu bar can lag
-- behind `front_app_switched`, causing the helper to temporarily return the
-- previous app's menu. Debounce and retry a few times to avoid getting stuck
-- with stale menus after switching apps.
--
-- Note: `front_app_switched` can report a generic process name (e.g. "Electron")
-- for some apps, so we key change detection off the helper output instead of
-- `$INFO`.
--
-- Some apps, including Zotero, can publish their native menu bar incrementally
-- after focus changes. Wait for the new app to appear, then keep sampling that
-- same app briefly and prefer the richest snapshot collected in that settle
-- window so we do not lock in a partial menu.
local MAX_UPDATE_RETRIES = 8
local RETRY_BASE_DELAY_S = 0.20
local MENU_SETTLE_RETRIES = 4
local MENU_SETTLE_DELAY_S = 0.18
local SUSPEND_RETRY_DELAY_S = 0.25

local last_rendered_menu_app = ""
local last_rendered_menu_signature = ""
local request_token = 0

local debounce_id = 0
local timer_armed = false

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parse_menus(menus)
  local parsed = {
    raw = menus or "",
    app = "",
    count = 0,
    titles = {},
  }

  for menu in string.gmatch(menus or "", "[^\r\n]+") do
    local menu_title = trim(menu)
    if menu_title ~= "" then
      parsed.titles[#parsed.titles + 1] = menu_title
      if parsed.app == "" then parsed.app = menu_title end
    end
  end

  parsed.count = #parsed.titles
  return parsed
end

local function render_menus(parsed)
  sbar.set('/menu\\..*/', { drawing = false })
  menu_padding:set({ drawing = true })

  local id = 1
  for _, menu_title in ipairs(parsed.titles) do
    if id <= max_items then
      menu_items[id]:set({ label = menu_title, drawing = true })
      id = id + 1
    else
      break
    end
  end
end

local function apply_render(parsed)
  if parsed.count <= 0 or parsed.app == "" then return end

  if parsed.raw ~= last_rendered_menu_signature then
    render_menus(parsed)
    last_rendered_menu_signature = parsed.raw
  end

  last_rendered_menu_app = parsed.app
end

local function retry_delay(attempt)
  return RETRY_BASE_DELAY_S * (attempt + 1)
end

local update_menus_with_retries

local function schedule_retry(token, expects_change, baseline_menu_app, attempt, target_app, best_candidate, settle_retries_left, delay_s)
  sbar.delay(delay_s, function()
    update_menus_with_retries(
      token,
      expects_change,
      baseline_menu_app,
      attempt + 1,
      target_app,
      best_candidate,
      settle_retries_left
    )
  end)
end

local function same_candidate(a, b)
  return a and b and a.app == b.app and a.raw == b.raw
end

local function select_best_candidate(current_best, parsed)
  if not current_best then
    return parsed, true
  end

  if parsed.app ~= current_best.app then
    return current_best, false
  end

  if parsed.count > current_best.count then
    return parsed, true
  end

  if parsed.count == current_best.count then
    return parsed, parsed.raw ~= current_best.raw
  end

  return current_best, false
end

update_menus_with_retries = function(token, expects_change, baseline_menu_app, attempt, target_app, best_candidate, settle_retries_left)
  settle_retries_left = settle_retries_left or MENU_SETTLE_RETRIES
  if token ~= request_token then return end

  if _G.SKETCHYBAR_SUSPENDED then
    sbar.delay(SUSPEND_RETRY_DELAY_S, function()
      update_menus_with_retries(token, expects_change, baseline_menu_app, attempt, target_app, best_candidate, settle_retries_left)
    end)
    return
  end

  sbar.exec("$CONFIG_DIR/helpers/menus/bin/menus -l", function(menus, exit_code)
    if token ~= request_token then return end

    if _G.SKETCHYBAR_SUSPENDED then
      if attempt < MAX_UPDATE_RETRIES then
        schedule_retry(token, expects_change, baseline_menu_app, attempt, target_app, best_candidate, settle_retries_left, SUSPEND_RETRY_DELAY_S)
      end
      return
    end

    if tonumber(exit_code) ~= 0 then
      if attempt < MAX_UPDATE_RETRIES then
        schedule_retry(token, expects_change, baseline_menu_app, attempt, target_app, best_candidate, settle_retries_left, retry_delay(attempt))
      end
      return
    end

    local parsed = parse_menus(menus)
    if parsed.app == "" or parsed.app == "Dock" then
      if attempt < MAX_UPDATE_RETRIES then
        schedule_retry(token, expects_change, baseline_menu_app, attempt, target_app, best_candidate, settle_retries_left, retry_delay(attempt))
      end
      return
    end

    -- If we expected an app change but still see the currently rendered menu,
    -- the native menu bar likely hasn't switched yet. Retry briefly.
    if expects_change and not target_app and parsed.app == baseline_menu_app then
      if attempt < MAX_UPDATE_RETRIES then
        schedule_retry(token, expects_change, baseline_menu_app, attempt, target_app, best_candidate, settle_retries_left, retry_delay(attempt))
      end
      return
    end

    if not target_app then
      target_app = parsed.app
    end

    if parsed.app ~= target_app then
      if attempt < MAX_UPDATE_RETRIES then
        schedule_retry(token, expects_change, baseline_menu_app, attempt, target_app, best_candidate, settle_retries_left, MENU_SETTLE_DELAY_S)
      end
      return
    end

    local candidate, changed = select_best_candidate(best_candidate, parsed)
    if not candidate then return end

    if changed or not same_candidate(candidate, best_candidate) then
      apply_render(candidate)
    end

    if attempt < MAX_UPDATE_RETRIES and settle_retries_left > 0 then
      schedule_retry(token, expects_change, baseline_menu_app, attempt, target_app, candidate, settle_retries_left - 1, MENU_SETTLE_DELAY_S)
      return
    end

    apply_render(candidate)
  end)
end

local function request_update(expects_change)
  local baseline_menu_app = last_rendered_menu_app
  request_token = request_token + 1
  local token = request_token
  update_menus_with_retries(token, expects_change == true, baseline_menu_app, 0, nil, nil, MENU_SETTLE_RETRIES)
end

local function schedule_update_menus(_)
  debounce_id = debounce_id + 1
  local id = debounce_id
  if timer_armed then return end
  timer_armed = true

  sbar.delay(SWITCH_DEBOUNCE_S, function()
    timer_armed = false
    if id ~= debounce_id then
      schedule_update_menus()
      return
    end

    request_update(true)
  end)
end

menu_watcher:subscribe("front_app_switched", schedule_update_menus)
-- Defer the initial read until the Lua event loop is running (reload-safe).
sbar.delay(0.1, function()
  request_update(false)
end)

return menu_watcher
