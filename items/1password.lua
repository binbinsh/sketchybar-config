local colors = require("colors")

-- Battery-style, bracket-less 1Password launcher:
-- - Left click: 1Password Quick Access (Cmd+Shift+Space)
-- - Right click: open 1Password app
local onepassword = sbar.add("item", "widgets.1password", {
  position = "right",
  icon = {
    string = ":one_password:",
    font = "sketchybar-app-font:Regular:15.0",
    color = colors.white,
  },
  label = { drawing = false },
  background = { drawing = false },
  -- Match `items/battery.lua` outer spacing.
  padding_left = 0,
  padding_right = 0,
  updates = false,
})

onepassword:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("/bin/zsh -lc 'open -a \"1Password\"' >/dev/null 2>&1", function() end)
    return
  end
  if env.BUTTON ~= "left" then return end
  sbar.exec("osascript -e 'tell application \"System Events\" to key code 49 using {command down, shift down}'")
end)

return onepassword

