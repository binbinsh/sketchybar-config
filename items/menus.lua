local colors = require("colors")
local settings = require("settings")

local menu_watcher = sbar.add("item", {
  drawing = false,
  updates = true,
})

-- App-switch responsiveness:
-- Keep this slightly conservative for stability (hardcore simplified: no retries).
local SWITCH_DEBOUNCE_S = 0.45

-- Visual tuning (purely cosmetic)
local MENU_ITEM_GAP = 2         -- spacing between items
local MENU_LABEL_PADDING = 6    -- inner padding for each label

-- "Geek" panel theme (opaque enough to mask the native macOS menu bar text).
local MENU_PANEL_BG = colors.cyber
local MENU_PANEL_BORDER = colors.green

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
    height = 28,
    corner_radius = 9,
    border_width = 2,
    -- Not "black": use a lighter tint, still opaque enough to mask the native menu.
    color = colors.with_alpha(MENU_PANEL_BG, 0.92),
    border_color = colors.with_alpha(MENU_PANEL_BORDER, 0.90),
  },
})

local menu_padding = sbar.add("item", "menu.padding", {
  drawing = false,
  width = settings.group_paddings,
})

-- Mission Control frequently switches the "front app" to Dock.
-- Avoid running the expensive menus helper unless the *real* front app changed.
-- NOTE: These must be declared *before* `update_menus` so the function closes over
-- the correct locals (Lua resolves locals lexically).
local last_app = ""
local debounce_id = 0
local timer_armed = false
local latest_app = ""

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function render_menus(menus)
  sbar.set('/menu\\..*/', { drawing = false })
  menu_padding:set({ drawing = true })

  local id = 1
  for menu in string.gmatch(menus or "", "[^\r\n]+") do
    menu = trim(menu)
    if menu ~= "" then
      if id <= max_items then
        menu_items[id]:set({ label = menu, drawing = true })
        id = id + 1
      else
        break
      end
    end
  end
end

local function update_menus()
  if _G.SKETCHYBAR_SUSPENDED then return end
  sbar.exec("$CONFIG_DIR/helpers/menus/bin/menus -l", function(menus, exit_code)
    if tonumber(exit_code) ~= 0 then return end
    render_menus(menus)
  end)
end

local function schedule_update_menus(env)
  latest_app = (env and env.INFO) or latest_app or ""
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

    local app = latest_app or ""
    if app == "" or app == "Dock" then return end
    if app == last_app then return end
    last_app = app
    update_menus()
  end)
end

menu_watcher:subscribe("front_app_switched", schedule_update_menus)
update_menus()

return menu_watcher
