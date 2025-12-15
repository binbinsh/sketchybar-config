local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local popup = require("helpers.popup")

local popup_width = 250

local function trim_newline(s)
  return (s or ""):gsub("\r", ""):gsub("\n$", "")
end

local function extract_tm_timestamp(s)
  local last = nil
  for ts in tostring(s or ""):gmatch("(%d%d%d%d%-%d%d%-%d%d%-%d%d%d%d%d%d)") do
    last = ts
  end
  return last
end

local function format_tm_timestamp(ts)
  if not ts or ts == "" then return nil end
  local y, mo, d, h, m = ts:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)%-(%d%d)(%d%d)%d%d$")
  if not y then return nil end
  return string.format("%s-%s-%s %s:%s", y, mo, d, h, m)
end

local function exec(cmd, cb)
  sbar.exec(cmd, cb)
end


-- no manual multi-line splitting needed now

local function build_jxa_cmd(js_lines, argv)
  local parts = {}
  for _, line in ipairs(js_lines) do
    parts[#parts + 1] = "-e " .. string.format("%q", line)
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
      family = settings.font.icons,
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
})

-- Create bracket for popup attachment
local tm_bracket = sbar.add("bracket", "widgets.time_machine.bracket", {
  tm.name,
}, {
  background = { drawing = false },
  popup = { align = "center" }
})

popup.register(tm_bracket)

tm:subscribe("mouse.entered", function(_)
  tm:set({ icon = { color = colors.blue } })
end)

tm:subscribe("mouse.exited", function(_)
  tm:set({ icon = { color = colors.white } })
end)


-- Popup items
-- Title row
local title_item = sbar.add("item", {
  position = "popup." .. tm_bracket.name,
  icon = {
    font = { style = settings.font.style_map["Bold"] },
    string = icons.time_machine,
  },
  width = popup_width,
  align = "center",
  label = {
    font = { size = 15, style = settings.font.style_map["Bold"] },
    string = "Time Machine",
  },
  background = { height = 2, color = colors.grey, y_offset = -15 },
})

-- Status row under title
local status_row = sbar.add("item", {
  position = "popup." .. tm_bracket.name,
  width = popup_width,
  icon = { align = "left", string = "Status:", width = popup_width / 2 },
  label = { align = "right", string = "—", width = popup_width / 2 },
})

-- Latest single row
local latest_row = sbar.add("item", {
  position = "popup." .. tm_bracket.name,
  width = popup_width,
  icon = { align = "left", string = "Latest:", width = popup_width / 2 },
  label = { align = "right", string = "—", width = popup_width / 2 },
})

-- Actions stacked under latest
local action_start = sbar.add("item",
  { position = "popup." .. tm_bracket.name, width = popup_width, icon = { align = "left", string = "Start backup", width = popup_width }, label = { drawing = false } })
local action_stop = sbar.add("item",
  { position = "popup." .. tm_bracket.name, width = popup_width, icon = { align = "left", string = "Stop backup", width = popup_width }, label = { drawing = false } })
local action_open_dest = sbar.add("item",
  { position = "popup." .. tm_bracket.name, width = popup_width, icon = { align = "left", string = "Open destination", width = popup_width }, label = { drawing = false } })
local action_open_tm = sbar.add("item",
  { position = "popup." .. tm_bracket.name, width = popup_width, icon = { align = "left", string = "Open Time Machine", width = popup_width }, label = { drawing = false } })

local function populate_tm_details()
  -- Update status
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
    status_row:set({ label = { string = status } })
  end)

  local function set_latest(text)
    text = trim_newline(text)
    if text == "" then text = "—" end
    latest_row:set({ label = { string = text } })
  end

  exec("/usr/bin/tmutil latestbackup 2>&1", function(out, exit_code)
    local formatted = nil
    if tonumber(exit_code) == 0 then
      formatted = format_tm_timestamp(extract_tm_timestamp(out))
      if formatted then
        set_latest(formatted)
      else
        set_latest("No backups found")
      end
      return
    end

    local err = tostring(out or "")
    exec("/usr/bin/defaults read /Library/Preferences/com.apple.TimeMachine LastBackupActivity 2>/dev/null", function(fallback, defaults_code)
      if tonumber(defaults_code) == 0 then
        formatted = format_tm_timestamp(extract_tm_timestamp(fallback))
      end
      if formatted then
        set_latest(formatted)
        return
      end

      local err_lc = err:lower()
      if err_lc:find("full disk access", 1, true)
          or err_lc:find("not permitted", 1, true)
          or err_lc:find("not authorized", 1, true)
          or err_lc:find("operation not permitted", 1, true) then
        set_latest("Full Disk Access required")
        return
      end

      if err_lc:find("no backups", 1, true)
          or err_lc:find("no destination", 1, true)
          or err_lc:find("no destinations", 1, true)
          or err_lc:find("not configured", 1, true) then
        set_latest("No backups found")
        return
      end

      local first_line = err:match("([^\r\n]+)") or ""
      first_line = first_line:gsub("^%s+", ""):gsub("%s+$", "")
      set_latest(first_line ~= "" and first_line or "—")
    end)
  end)
end

-- Click handlers for actions (stacked)
action_start:subscribe("mouse.clicked", function(_)
  exec(jxa_admin_cmd("tmutil startbackup"), function(_)
    sbar.delay(0.5, function() populate_tm_details() end)
  end)
end)

action_stop:subscribe("mouse.clicked", function(_)
  exec(jxa_admin_cmd("tmutil stopbackup"), function(_)
    sbar.delay(0.5, function() populate_tm_details() end)
  end)
end)

action_open_dest:subscribe("mouse.clicked", function(_)
  local cmd =
  [[/bin/zsh -lc 'tmutil destinationinfo 2>/dev/null | grep "^URL" | head -n1 | cut -d: -f2- | sed -E "s/^ +//; s/ +$//"']]
  exec(cmd, function(url)
    url = (url or ""):gsub("\n$", "")
    if url ~= "" then
      exec("/bin/zsh -lc 'open \"" .. url .. "\"'", function(_) end)
    else
      exec(
        "/bin/zsh -lc 'open \"x-apple.systempreferences:com.apple.TimeMachine-Settings.extension\" || open -a \"Time Machine\"'",
        function(_) end)
    end
  end)
end)

action_open_tm:subscribe("mouse.clicked", function(_)
  exec("/bin/zsh -lc 'open -a \"Time Machine\"'", function(_) end)
end)

tm:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("open 'x-apple.systempreferences:com.apple.TimeMachine-Settings.extension'")
    return
  end
  if env.BUTTON ~= "left" then return end
  popup.toggle(tm_bracket, populate_tm_details)
end)

popup.auto_hide(tm_bracket, tm)
