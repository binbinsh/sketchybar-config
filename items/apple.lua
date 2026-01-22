local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

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
    drawing = false,
  }
})

-- Padding item required because of bracket
sbar.add("item", { width = 7 })
