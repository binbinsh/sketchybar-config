local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local popup = require("helpers.popup")

local popup_width = 200

local function trim_newline(s)
  return (s or ""):gsub("\r", ""):gsub("\n$", "")
end

local function exec(cmd, cb)
  sbar.exec(cmd, cb)
end


-- no manual multi-line splitting needed now

local function build_jxa_cmd(js_lines, argv)
  local parts = {}
  for _, line in ipairs(js_lines) do
    parts[#parts+1] = "-e " .. string.format("%q", line)
  end
  local cmd = "/usr/bin/osascript -l JavaScript " .. table.concat(parts, " ")
  if argv then cmd = cmd .. " -- " .. string.format("%q", argv) end
  return cmd
end

local function jxa_admin_cmd(shell_cmd)
  local js_lines = {
    "function run(argv) {",
    "  var cmd = argv[0];",
    "  var app = Application.currentApplication();",
    "  app.includeStandardAdditions = true;",
    "  try { return app.doShellScript(cmd, {administratorPrivileges: true}); } catch (e) { return String(e); }",
    "}"
  }
  return build_jxa_cmd(js_lines, shell_cmd)
end

-- Time Machine widget
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

-- Popup items
local title_item = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = {
    font = { style = settings.font.style_map["Bold"] },
    string = icons.time_machine,
  },
  width = popup_width,
  align = "center",
  label = {
    font = { size = 15, style = settings.font.style_map["Bold"] },
    string = "—",
  },
  background = { height = 2, color = colors.grey, y_offset = -15 },
})
-- Single-column layout under title
-- Recent backups heading then up to 3 times
local recent_row1 = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = { align = "center", string = "Recent backups:", width = popup_width },
  label = { drawing = false },
})
local recent_row2 = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = { align = "left", string = "", width = 0 },
  label = { align = "center", string = "", width = popup_width },
})
local recent_row3 = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = { align = "left", string = "", width = 0 },
  label = { align = "center", string = "", width = popup_width },
})
local recent_row4 = sbar.add("item", {
  position = "popup." .. tm.name,
  icon = { align = "left", string = "", width = 0 },
  label = { align = "center", string = "", width = popup_width },
})

-- Divider between info and actions
local divider_item = sbar.add("item", {
  position = "popup." .. tm.name,
  width = popup_width,
  background = { height = 2, color = colors.grey, y_offset = -5 },
})

-- Actions
local start_btn = sbar.add("item", {
  position = "popup." .. tm.name,
  width = popup_width,
  align = "center",
  icon = { string = icons.refresh },
  label = { string = "Start backup" },
})

local stop_btn = sbar.add("item", {
  position = "popup." .. tm.name,
  width = popup_width,
  align = "center",
  icon = { string = icons.media and icons.media.play_pause or "⏸" },
  label = { string = "Stop backup" },
})

local open_dest_btn = sbar.add("item", {
  position = "popup." .. tm.name,
  width = popup_width,
  align = "center",
  icon = { string = (icons.link or icons.gear) },
  label = { string = "Open destination" },
})

local open_tm_btn = sbar.add("item", {
  position = "popup." .. tm.name,
  width = popup_width,
  align = "center",
  icon = { string = icons.time_machine },
  label = { string = "Open Time Machine" },
})

local function populate_tm_details()
  title_item:set({ label = "—" })

  -- Status (Idle/Running) shown in title
  local status_cmd = [[/bin/zsh -lc '
    out=$(tmutil status 2>/dev/null || true)
    if printf "%s" "$out" | grep -q "Running = 1"; then
      echo Running
    else
      echo Idle
    fi
  ']]
  exec(status_cmd, function(out)
    local status = trim_newline(out)
    if status == "" then status = "—" end
    title_item:set({ label = status })
  end)

  -- Recent backups (up to 3)
  local recent_cmd = [[/bin/zsh -lc '
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
  exec(recent_cmd, function(result)
    local text = trim_newline(result)
    local lines = {}
    for line in string.gmatch(text, "([^\n]+)") do
      if line and line ~= "" then table.insert(lines, line) end
    end
    if #lines == 0 then
      recent_row2:set({ label = { string = "", align = "center", width = popup_width } })
      recent_row3:set({ label = { string = "", align = "center", width = popup_width } })
      recent_row4:set({ label = { string = "", align = "center", width = popup_width } })
      return
    end
    recent_row2:set({ label = { string = lines[1] or "", align = "center", width = popup_width } })
    recent_row3:set({ label = { string = lines[2] or "", align = "center", width = popup_width } })
    recent_row4:set({ label = { string = lines[3] or "", align = "center", width = popup_width } })
  end)
end

-- Click handlers

start_btn:subscribe("mouse.clicked", function(_)
  exec(jxa_admin_cmd("tmutil startbackup"), function(_)
    sbar.delay(0.5, function() populate_tm_details() end)
  end)
end)

stop_btn:subscribe("mouse.clicked", function(_)
  exec(jxa_admin_cmd("tmutil stopbackup"), function(_)
    sbar.delay(0.5, function() populate_tm_details() end)
  end)
end)

open_dest_btn:subscribe("mouse.clicked", function(_)
  local cmd = [[/bin/zsh -lc 'tmutil destinationinfo 2>/dev/null | grep "^URL" | head -n1 | cut -d: -f2- | sed -E "s/^ +//; s/ +$//"']]
  exec(cmd, function(url)
    url = (url or ""):gsub("\n$", "")
    if url ~= "" then
      exec("/bin/zsh -lc 'open \"" .. url .. "\"'", function(_) end)
    else
      exec("/bin/zsh -lc 'open \"x-apple.systempreferences:com.apple.TimeMachine-Settings.extension\" || open -a \"Time Machine\"'", function(_) end)
    end
  end)
end)

open_tm_btn:subscribe("mouse.clicked", function(_)
  exec("/bin/zsh -lc 'open -a \"Time Machine\"'", function(_) end)
end)

tm:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("open 'x-apple.systempreferences:com.apple.TimeMachine-Settings.extension'")
    return
  end
  if env.BUTTON ~= "left" then return end
  popup.toggle(tm, populate_tm_details)
end)

popup.auto_hide(tm)

-- Mark wiring tasks complete: toggle already wired to item and auto hide enabled

