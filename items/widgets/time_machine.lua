local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local popup = require("helpers.popup")

local popup_width = 250

local function trim_newline(s)
  return (s or ""):gsub("\r", ""):gsub("\n$", "")
end

-- Time Machine minimal widget
local tm = sbar.add("item", "widgets.time_machine", {
  position = "right",
  icon = {
    string = icons.time_machine,
    font = {
      family = settings.font.text,
      style = settings.font.style_map["Regular"],
      size = 16.0,
    },
    color = colors.white,
  },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = settings.paddings,
  padding_right = settings.paddings,
  updates = true,
  popup = { align = "center" },
})

popup.register(tm)

tm:subscribe("mouse.entered", function(_)
  tm:set({ icon = { color = colors.blue } })
end)

tm:subscribe("mouse.exited", function(_)
  tm:set({ icon = { color = colors.white } })
end)

-- Popup content
local tm_title = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = {
    align = "left",
    string = "Last backups:",
    width = popup_width,
  },
  label = { drawing = false },
})

local tm_value1 = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = { drawing = false },
  label = {
    string = "…",
    width = popup_width,
    align = "left",
  },
})

-- Additional lines for multi-line display (show up to 3 backups)
local tm_value2 = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = { drawing = false },
  label = {
    string = "",
    width = popup_width,
    align = "left",
  },
})

local tm_value3 = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = { drawing = false },
  label = {
    string = "",
    width = popup_width,
    align = "left",
  },
})

tm:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("open -a 'Time Machine'")
    return
  end

  if env.BUTTON ~= "left" then return end

  popup.toggle(tm, function()
    tm_value1:set({ label = "…" })
    local cmd = [[/bin/zsh -lc '
      out=$(tmutil listbackups 2>&1); code=$?
      if [ $code -ne 0 ] || printf "%s" "$out" | grep -qiE "not permitted|not authorized"; then
        echo "Full Disk Access required"
      else
        ts=$(printf "%s\n" "$out" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}" | sort -ru | head -n3)
        if [ -n "$ts" ]; then
          printf "%s\n" "$ts" | while IFS= read -r l; do
            date_part=$(printf "%s" "$l" | cut -c1-10)
            h=$(printf "%s" "$l" | cut -c12-13)
            m=$(printf "%s" "$l" | cut -c14-15)
            printf "%s %s:%s\n" "$date_part" "$h" "$m"
          done
        else
          echo "No backups found"
        fi
      fi
    ']]
    sbar.exec(cmd, function(result)
      local text = trim_newline(result)
      local lines = {}
      for line in string.gmatch(text, "([^\n]+)") do
        table.insert(lines, line)
      end

      if #lines == 0 then
        tm_value1:set({ label = text })
        tm_value2:set({ label = "" })
        tm_value3:set({ label = "" })
        return
      end

      tm_value1:set({ label = lines[1] or "" })
      tm_value2:set({ label = lines[2] or "" })
      tm_value3:set({ label = lines[3] or "" })
    end)
  end)
end)

popup.auto_hide(tm)


