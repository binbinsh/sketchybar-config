local colors = require("colors")
local settings = require("settings")
local popup = require("helpers.popup")
local icons = require("icons")

-- Popup contents
local popup_width = 200

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
    scale = 0.28,
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
  updates = false,
})

-- Create bracket for popup attachment
local synergy_bracket = sbar.add("bracket", "widgets.synergy.bracket", {
  synergy.name,
}, {
  background = { drawing = false },
  popup = { align = "center" }
})

popup.register(synergy_bracket)

-- Hover behavior: gray when idle, color on hover
synergy:subscribe("mouse.entered", function(_)
  synergy:set({ background = { image = { string = synergy_icon_path } } })
end)

synergy:subscribe("mouse.exited", function(_)
  synergy:set({ background = { image = { string = synergy_gray_icon_path } } })
end)

local check_cmd = [=[/bin/zsh -lc '
main="STOPPED"
if /usr/bin/osascript -e "tell application \"System Events\" to (exists process \"Synergy\")" | grep -qi true; then main="RUNNING"; fi
server="STOPPED"; if /usr/bin/pgrep -f -q "(^|/)synergy-server([[:space:]]|$)"; then server="RUNNING"; fi
client="STOPPED"; if /usr/bin/pgrep -f -q "(^|/)synergy-client([[:space:]]|$)"; then client="RUNNING"; fi
echo "main:$main"
echo "server:$server"
echo "client:$client"
']=]

local title_item = sbar.add("item", {
  position = "popup." .. synergy_bracket.name,
  icon = {
    drawing = true,
    string = icons.synergy,
  },
  width = popup_width,
  align = "center",
  label = {
    font = { size = 15, style = settings.font.style_map["Bold"] },
    string = "Synergy",
    align = "center",
  },
  background = { height = 2, color = colors.grey, y_offset = -15 },
})

local function new_row()
  return sbar.add("item", {
    position = "popup." .. synergy_bracket.name,
    width = popup_width,
    icon = { align = "left", string = "", width = popup_width / 2 },
    label = { align = "right", string = "", width = popup_width / 2 },
  })
end

local row2 = new_row() -- Main: | status
local row3 = new_row() -- Server: | status
local row4 = new_row() -- Client: | status

local function populate_popup()
  row2:set({ icon = { string = "Main:" } })
  row3:set({ icon = { string = "Server:" } })
  row4:set({ icon = { string = "Client:" } })

  sbar.exec(check_cmd, function(out)
    local o = out or ""
    local main = o:match("main:(%w+)") or "STOPPED"
    local server = o:match("server:(%w+)") or "STOPPED"
    local client = o:match("client:(%w+)") or "STOPPED"
    row2:set({ label = { string = main } })
    row3:set({ label = { string = server } })
    row4:set({ label = { string = client } })
  end)
end


local open_main_cmd = [=[/bin/zsh -lc '
# Open Synergy if not running
if ! /usr/bin/osascript -e "tell application \"System Events\" to (exists process \"Synergy\")" | grep -qi true; then
  open -ga "Synergy"
  sleep 1
fi

# Click menu bar and show window
/usr/bin/osascript <<APPLESCRIPT
tell application "System Events"
  tell process "Synergy"
    click menu bar item 1 of menu bar 2
    click menu item "Show" of menu 1 of menu bar item 1 of menu bar 2
  end tell
  set frontmost of process "Synergy" to true
end tell
APPLESCRIPT
']=]


-- Click handlers: left shows status popup; right shows main window
synergy:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then
    popup.toggle(synergy_bracket, populate_popup)
    return
  end
  if env.BUTTON == "right" then
    sbar.exec(open_main_cmd, function()
      popup.hide(synergy_bracket)
    end)
    return
  end
end)

-- Auto-hide popup on context changes
popup.auto_hide(synergy_bracket, synergy)
