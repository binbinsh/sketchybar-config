local colors = require("colors")
local settings = require("settings")
local popup = require("helpers.popup")

local synergy_icon_path = os.getenv("HOME") .. "/.config/sketchybar/icons/synergy.png"
local synergy_gray_icon_path = os.getenv("HOME") .. "/.config/sketchybar/icons/synergy_gray.png"

-- Render Synergy PNG logo with a transparent background (no colored box)
local synergy = sbar.add("item", "widgets.synergy", {
  position = "right",
  icon = { drawing = false },
  label = { drawing = false },
  background = {
    drawing = true,
    image = {
      string = synergy_gray_icon_path,
    scale = 0.26,
      border_width = 0,
      border_color = colors.transparent,
      corner_radius = 0,
    },
    color = colors.transparent,
    border_width = 0,
    border_color = colors.transparent,
    corner_radius = 0,
  },
  padding_left = settings.paddings,
  padding_right = settings.paddings,
  popup = { align = "center" },
  updates = true,
})

popup.register(synergy)

-- Hover behavior: gray when idle, color on hover
synergy:subscribe("mouse.entered", function(_)
  synergy:set({ background = { image = { string = synergy_icon_path } } })
end)

synergy:subscribe("mouse.exited", function(_)
  synergy:set({ background = { image = { string = synergy_gray_icon_path } } })
end)

local check_cmd = [=[/bin/zsh -lc '
main="stopped"
if /usr/bin/osascript -e "tell application \"System Events\" to (exists process \"Synergy\")" | grep -qi true; then main="running"; fi
server="stopped"; if /usr/bin/pgrep -f -q "(^|/)synergy-server([[:space:]]|$)"; then server="running"; fi
client="stopped"; if /usr/bin/pgrep -f -q "(^|/)synergy-client([[:space:]]|$)"; then client="running"; fi
echo "main:$main"
echo "server:$server"
echo "client:$client"
']=]

-- Popup contents
local status_title = sbar.add("item", {
  position = "popup." .. synergy.name,
  icon = { align = "left", string = "Synergy:" },
  label = { drawing = false },
})

local status_main = sbar.add("item", {
  position = "popup." .. synergy.name,
  icon = { align = "left", string = "main is " },
  label = { string = "…", align = "left" },
})

local status_server = sbar.add("item", {
  position = "popup." .. synergy.name,
  icon = { align = "left", string = "server is " },
  label = { string = "…", align = "left" },
})

local status_client = sbar.add("item", {
  position = "popup." .. synergy.name,
  icon = { align = "left", string = "client is " },
  label = { string = "…", align = "left" },
})

local function populate_popup()
  sbar.exec(check_cmd, function(out)
    local o = out or ""
    local main = o:match("main:(%w+)") or "stopped"
    local server = o:match("server:(%w+)") or "stopped"
    local client = o:match("client:(%w+)") or "stopped"
    status_main:set({ label = main })
    status_server:set({ label = server })
    status_client:set({ label = client })
  end)
end


local open_main_cmd = [=[/bin/zsh -lc '
open -ga "Synergy" || true

/usr/bin/osascript <<APPLESCRIPT
tell application "Synergy" to reopen

set hasWindow to false
tell application "System Events"
  if exists process "Synergy" then
    tell process "Synergy"
      set hasWindow to (exists window 1)
    end tell
  end if
end tell

if hasWindow is false then
  tell application "System Events"
    if not (exists process "Synergy") then return
    tell process "Synergy"
      click menu bar item 1 of menu bar 2
      click menu item "Show" of menu 1 of menu bar item 1 of menu bar 2
    end tell
  end tell
end if
APPLESCRIPT
']=]


-- Click handlers: left shows status popup; right show main window
synergy:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then
    popup.toggle(synergy, populate_popup)
    return
  end
  if env.BUTTON == "right" then
    sbar.exec(open_main_cmd, function()
      popup.hide(synergy)
    end)
    return
  end
end)

-- Auto-hide popup on context changes
popup.auto_hide(synergy)
