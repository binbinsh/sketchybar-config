local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

-- Geek panel theme (match `items/menus.lua`).
local APPLE_PANEL_BG = colors.cyber
local APPLE_PANEL_BORDER = colors.magenta

-- Padding item required because of bracket
sbar.add("item", { width = 5 })

local apple = sbar.add("item", {
  icon = {
    font = { family = settings.font.icons, size = 18.0 },
    string = icons.apple,
    padding_right = 8,
    padding_left = 8,
  },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = 0,
  padding_right = 0,
  click_script = "$CONFIG_DIR/helpers/menus/bin/menus -s 0"
})

-- Cyber-style pill background to mask the native macOS menu bar behind it.
sbar.add("bracket", "apple.bracket", { apple.name }, {
  background = {
    height = 28,
    corner_radius = 9,
    border_width = 2,
    color = colors.with_alpha(APPLE_PANEL_BG, 0.92),
    border_color = colors.with_alpha(APPLE_PANEL_BORDER, 0.90),
  }
})

-- Padding item required because of bracket
sbar.add("item", { width = 7 })
