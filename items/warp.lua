local colors = require("colors")

-- Compact Cloudflare WARP menu shortcut.
local warp = sbar.add("item", "widgets.warp", {
  position = "right",
  icon = {
    string = ":cloud:",
    font = "sketchybar-app-font:Regular:15.0",
    color = colors.white,
  },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = 0,
  padding_right = 0,
  updates = false,
})

local open_warp_menu = table.concat({
  "osascript",
  [[-e 'set warp_process to "Cloudflare WARP"']],
  [[-e 'set warp_app to "/Applications/Cloudflare WARP.app"']],
  [[-e 'tell application "System Events"']],
  [[-e '  if exists process warp_process then']],
  [[-e '    tell process warp_process']],
  [[-e '      if (exists menu bar 1) and ((count of menu bar items of menu bar 1) > 0) then']],
  [[-e '        click menu bar item 1 of menu bar 1']],
  [[-e '        return']],
  [[-e '      end if']],
  [[-e '    end tell']],
  [[-e '  end if']],
  [[-e 'end tell']],
  [[-e 'do shell script "open -a " & quoted form of warp_app']],
  [[-e 'repeat 12 times']],
  [[-e '  delay 0.25']],
  [[-e '  tell application "System Events"']],
  [[-e '    if exists process warp_process then']],
  [[-e '      tell process warp_process']],
  [[-e '        if (exists menu bar 1) and ((count of menu bar items of menu bar 1) > 0) then']],
  [[-e '          click menu bar item 1 of menu bar 1']],
  [[-e '          return']],
  [[-e '        end if']],
  [[-e '      end tell']],
  [[-e '    end if']],
  [[-e '  end tell']],
  [[-e 'end repeat']],
}, " ")

warp:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" and env.BUTTON ~= "right" then return end
  sbar.exec(open_warp_menu, function() end)
end)

return warp
