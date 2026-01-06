local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

local function pick_env_or_setting(env_key, setting_key)
  local value = os.getenv(env_key)
  if value and value ~= "" then return value end
  value = settings[setting_key]
  if value and value ~= "" then return value end
  return nil
end

local CCADAPTER_ALIAS = os.getenv("CCADAPTER_ALIAS") or "ccadapter"
local CCADAPTER_APP = os.getenv("CCADAPTER_APP") or "ccadapter"
local CCADAPTER_LAUNCH = "/Applications/CCAdapter.app/Contents/MacOS/ccadapter --show-tray"
local CONFIG_DIR = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")
local MENUS_BIN = CONFIG_DIR .. "/helpers/menus/bin/menus"

local function shell_quote(value)
  if value == nil then return "''" end
  value = tostring(value)
  if value == "" then return "''" end
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function try_select_menu(alias, done)
  if not alias or alias == "" then
    if done then done(false) end
    return
  end
  sbar.exec(MENUS_BIN .. " -s " .. shell_quote(alias) .. " >/dev/null 2>&1", function(_, exit_code)
    if done then done(tonumber(exit_code) == 0) end
  end)
end

local function launch_ccadapter()
  if CCADAPTER_LAUNCH and CCADAPTER_LAUNCH ~= "" then
    sbar.exec(CCADAPTER_LAUNCH, function() end)
    return
  end
  sbar.exec("/usr/bin/open -gja " .. shell_quote(CCADAPTER_APP) .. " >/dev/null 2>&1", function() end)
end

local ccadapter = sbar.add("item", "widgets.ccadapter", {
  position = "right",
  icon = {
    string = icons.adapter,
    font = {
      family = settings.font.icons,
      style = settings.font.style_map["Regular"],
      size = 15.0,
    },
    color = colors.white,
    padding_left = 4,
    padding_right = 4,
  },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = 0,
  padding_right = 0,
  updates = false,
})

local function open_ccadapter_menu()
  if CCADAPTER_LAUNCH and CCADAPTER_LAUNCH ~= "" then
    sbar.exec(CCADAPTER_LAUNCH, function() end)
    return
  end
  try_select_menu(CCADAPTER_ALIAS, function(ok)
    if ok then return end
    launch_ccadapter()
    sbar.delay(0.2, function()
      try_select_menu(CCADAPTER_ALIAS, function() end)
    end)
  end)
end

ccadapter:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" then return end
  open_ccadapter_menu()
end)

return ccadapter
