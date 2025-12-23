local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("app_icons")
local center_popup = require("center_popup")

local popup_width = 520
local name_col_w = 190
local value_col_w = popup_width - name_col_w

local name_font = {
  family = settings.font.text,
  style = settings.font.style_map["Semibold"],
  size = 13.0,
}

local value_font = {
  family = settings.font.text,
  style = settings.font.style_map["Regular"],
  size = 12.0,
}

local function app_icon(app_name, fallback, size)
  local icon = app_icons[app_name]
  local icon_size = size or 16.0
  if icon and icon ~= "" then
    return icon, "sketchybar-app-font:Regular:" .. tostring(icon_size)
  end
  return fallback, {
    family = settings.font.icons,
    style = settings.font.style_map["Regular"],
    size = icon_size,
  }
end

local function only_left_click(fn)
  return function(env)
    if env.BUTTON ~= "left" then return end
    fn(env)
  end
end

local function make_popup(id, title, meta)
  local popup = center_popup.create("shortcuts." .. id, {
    width = popup_width,
    height = 1,
    y_offset = 160,
    title = title,
    meta = meta or "",
    popup_height = 26,
  })

  popup.body_item:set({ drawing = false })

  local position = popup.position

  local function add_row(name, value, opts)
    opts = opts or {}
    local item = sbar.add("item", {
      position = position,
      width = popup_width,
      drawing = opts.drawing ~= false,
      icon = {
        align = "left",
        string = name or "",
        width = opts.name_width or name_col_w,
        font = opts.name_font or name_font,
      },
      label = {
        align = opts.label_align or "left",
        string = value or "",
        width = opts.value_width or value_col_w,
        font = opts.label_font or value_font,
        drawing = opts.label_drawing ~= false,
      },
    })

    if opts.on_click then
      item:subscribe("mouse.clicked", only_left_click(opts.on_click))
    end

    return item
  end

  local function add_action_row(text, on_click)
    return add_row(text, "", {
      name_width = popup_width,
      value_width = 0,
      label_drawing = false,
      name_font = {
        family = settings.font.text,
        style = settings.font.style_map["Semibold"],
        size = 12.5,
      },
      on_click = on_click,
    })
  end

  return {
    popup = popup,
    position = position,
    add_row = add_row,
    add_action_row = add_action_row,
  }
end

local function toggle_popup(popup, on_show)
  if popup.is_showing() then
    popup.hide()
    return
  end
  popup.show(on_show)
end

local function add_icon_item(key, icon_string, icon_font, popup, on_show, opts)
  opts = opts or {}
  local item = sbar.add("item", "widgets.shortcuts." .. key, {
    position = "right",
    icon = {
      string = icon_string,
      font = icon_font,
      color = colors.white,
    },
    label = opts.label or { drawing = false },
    background = { drawing = false },
    padding_left = settings.paddings,
    padding_right = settings.paddings,
    updates = true,
  })

  local function normal_color()
    if opts.icon_color then
      return opts.icon_color()
    end
    return colors.white
  end

  item:subscribe("mouse.entered", function(_)
    item:set({ icon = { color = colors.blue } })
  end)

  item:subscribe("mouse.exited", function(_)
    item:set({ icon = { color = normal_color() } })
  end)

  item:subscribe("mouse.clicked", only_left_click(function()
    toggle_popup(popup, on_show)
  end))

  return item
end

local clipboard_popup = make_popup("clipboard", "Clipboard", "Raycast Clipboard History")

clipboard_popup.add_row("History", "Open Raycast", {
  on_click = function()
    clipboard_popup.popup.hide()
    sbar.exec("open 'raycast://extensions/raycast/clipboard-history/clipboard-history'")
  end,
})

clipboard_popup.add_row("Ask Clipboard", "Open Raycast", {
  on_click = function()
    clipboard_popup.popup.hide()
    sbar.exec("open 'raycast://extensions/raycast/clipboard-history/ask-clipboard'")
  end,
})

local dictionary_popup = make_popup("dictionary", "Dictionary", "Raycast Translate")

dictionary_popup.add_row("Instant translate", "Open", {
  on_click = function()
    dictionary_popup.popup.hide()
    sbar.exec("open 'raycast://extensions/gebeto/translate/instant-translate-view'")
  end,
})

dictionary_popup.add_row("Quick translate", "Open", {
  on_click = function()
    dictionary_popup.popup.hide()
    sbar.exec("open 'raycast://extensions/gebeto/translate/quick-translate'")
  end,
})

local lm_popup = make_popup("lm_studio", "LM Studio", "Models and server")

lm_popup.add_action_row("Open app", function()
  lm_popup.popup.hide()
  sbar.exec("open -a 'LM Studio'")
end)

local lm_max_rows = 12
local lm_rows = {}
local lm_actions = {}

for i = 1, lm_max_rows, 1 do
  lm_rows[i] = sbar.add("item", {
    position = lm_popup.position,
    drawing = false,
    padding_left = settings.paddings,
    padding_right = settings.paddings,
    icon = { drawing = false },
    label = {
      font = {
        family = settings.font.text,
        style = settings.font.style_map["Semibold"],
        size = 13.0,
      },
      padding_left = 6,
      padding_right = 6,
    },
  })
end

for i = 1, lm_max_rows, 1 do
  local idx = i
  lm_rows[i]:subscribe("mouse.clicked", only_left_click(function(_)
    local fn = lm_actions[idx]
    if fn then fn() end
  end))
end

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalized_variants(value)
  local variants = {}
  local seen = {}

  local function add_variant(str)
    if not str or str == "" then return end
    if seen[str] then return end
    seen[str] = true
    table.insert(variants, str)
  end

  local cleaned = trim(value)
  if cleaned == "" then return variants end

  add_variant(cleaned:lower())

  local base = cleaned:match("([^/\\]+)$") or cleaned
  add_variant(base:lower())

  local no_ext = base:gsub("%.[^%.]+$", "")
  add_variant(no_ext:lower())

  return variants
end

local function mark_loaded_variant(set, value)
  for _, key in ipairs(normalized_variants(value)) do
    set[key] = true
  end
end

local function is_loaded_name(set, value)
  for _, key in ipairs(normalized_variants(value)) do
    if set[key] then return true end
  end
  return false
end

local function populate_lm_studio()
  for i = 1, lm_max_rows, 1 do
    lm_rows[i]:set({ drawing = false })
    lm_actions[i] = nil
  end

  local server_idx = 1
  local port_idx = 2
  local status_idx = 3
  local context_idx = 4
  local ttl_idx = 5
  local loaded_idx = 6
  local toggle_idx = 7
  local models_start_idx = 8

  local function set_kv(idx, key, value)
    lm_rows[idx]:set({
      drawing = true,
      width = popup_width,
      icon = {
        drawing = true,
        align = "left",
        string = key,
        width = popup_width / 2,
      },
      label = {
        align = "right",
        string = value,
        width = popup_width / 2,
      },
    })
  end

  local lms_prefix = [[LMS="$(command -v lms 2>/dev/null || { [ -x "$HOME/.lmstudio/bin/lms" ] && printf "%s" "$HOME/.lmstudio/bin/lms"; })"; ]]

  sbar.exec([[ /bin/zsh -lc ']] .. lms_prefix .. [[${LMS} status 2>/dev/null' ]], function(status_out)
    local on = (status_out or ""):match("Server:%s*ON") ~= nil
    local port = (status_out or ""):match("port:%s*(%d+)") or "-"
    set_kv(server_idx, "Server:", on and "ON" or "OFF")
    set_kv(port_idx, "Port:", port)

    local toggle_label = on and "Stop server" or "Start server"
    local toggle_cmd = on and "${LMS} server stop" or "nohup ${LMS} server start >/dev/null 2>&1 &"
    lm_rows[toggle_idx]:set({
      drawing = true,
      width = popup_width,
      label = toggle_label,
    })
    lm_actions[toggle_idx] = function()
      lm_popup.popup.hide()
      sbar.exec("/bin/zsh -lc '" .. lms_prefix .. toggle_cmd .. "'")
    end
  end)

  sbar.exec([[ /bin/zsh -lc ']] .. lms_prefix .. [[${LMS} ps 2>/dev/null' ]], function(ps_out)
    local function parse_size_to_bytes(sz)
      if not sz or sz == "" then return 0 end
      local num, unit = sz:match("([%d%.]+)%s*([A-Za-z]+)")
      num = tonumber(num or "0") or 0
      unit = (unit or "B"):upper()
      local mul = 1
      if unit == "KB" then mul = 1024
      elseif unit == "MB" then mul = 1024 * 1024
      elseif unit == "GB" then mul = 1024 * 1024 * 1024
      elseif unit == "TB" then mul = 1024 * 1024 * 1024 * 1024
      end
      return math.floor(num * mul)
    end

    local total = 0
    local first_status, first_context, first_ttl = nil, nil, nil
    local loaded_set = {}
    for line in string.gmatch(ps_out or "", "[^\r\n]+") do
      local s = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if s ~= "" and not s:match("^IDENTIFIER") and not s:match("^MODEL") and not s:match("^STATUS") and not s:match("^SIZE") then
        local ident, model, status, size_str, context, ttl = s:match("^(%S+)%s+(%S+)%s+(%S+)%s+([%d%.]+%s+[A-Za-z]+)%s*(%d*)%s*(%S*)")
        if size_str then
          total = total + parse_size_to_bytes(size_str)
        end
        if not first_status then
          first_status = status
          first_context = (context ~= nil and context ~= "" and context) or nil
          first_ttl = (ttl ~= nil and ttl ~= "" and ttl) or nil
        end
        if model and model ~= "" then mark_loaded_variant(loaded_set, model) end
        if ident and ident ~= "" then mark_loaded_variant(loaded_set, ident) end
      end
    end

    local function format_bytes(n)
      if n >= 1024*1024*1024 then return string.format("%.2f GB", n / (1024*1024*1024))
      elseif n >= 1024*1024 then return string.format("%.2f MB", n / (1024*1024))
      elseif n >= 1024 then return string.format("%.0f KB", n / 1024)
      else return tostring(n) .. " B" end
      end

    set_kv(loaded_idx, "Loaded:", format_bytes(total))
    if first_status and first_status ~= "" then set_kv(status_idx, "Status:", first_status) end
    if first_context and first_context ~= "" then set_kv(context_idx, "Context:", first_context) end
    if first_ttl and first_ttl ~= "" then set_kv(ttl_idx, "TTL:", first_ttl) end

    sbar.exec([[ /bin/zsh -lc ']] .. lms_prefix .. [[${LMS} ls 2>/dev/null' ]], function(out)
      local entries_models = {}

      local function parse_line(line)
        local s = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then return nil end
        if s:match("^EMBEDDING") or s:match("^LLM") or s:match("^PARAMS") or s:match("^ARCH") or s:match("^SIZE") then return nil end
        if s:match("^You have ") then return nil end
        local token = s:match("^(%S+)")
        if not token or token == "" then return nil end
        local is_embedding = token:lower():find("embed", 1, true) ~= nil
        if is_embedding then return nil end
        local loaded = is_loaded_name(loaded_set, token)
        return { name = token, loaded = loaded }
      end

      for line in string.gmatch(out or "", "[^\r\n]+") do
        local e = parse_line(line)
        if e then table.insert(entries_models, e) end
      end

      local idx = models_start_idx
      local usable_last = lm_max_rows - 1

      for _, e in ipairs(entries_models) do
        if idx > usable_last then break end
        local base = e.name:gsub(".*/", "")
        lm_rows[idx]:set({
          drawing = true,
          width = popup_width,
          icon = {
            drawing = true,
            align = "left",
            string = base,
            width = popup_width / 2,
          },
          label = {
            align = "right",
            string = e.loaded and "LOADED" or "",
            width = popup_width / 2,
          },
        })
        local row_index = idx
        local model_name = e.name
        local base_name = base
        lm_actions[row_index] = function()
          lm_popup.popup.hide()
          sbar.exec("/bin/zsh -lc '" .. lms_prefix
            .. 'nohup ${LMS} server start >/dev/null 2>&1 &; '
            .. '${LMS} unload --all; '
            .. '${LMS} load "' .. model_name .. '" --identifier "' .. base_name .. '" -y' .. "'")
        end
        idx = idx + 1
      end

      if idx == models_start_idx then
        lm_rows[models_start_idx]:set({
          drawing = true,
          width = popup_width,
          label = "Install lms CLI: ~/.lmstudio/bin/lms bootstrap",
        })
        lm_actions[models_start_idx] = function()
          lm_popup.popup.hide()
          sbar.exec("/bin/zsh -lc '" .. lms_prefix .. "${LMS} bootstrap || true'")
        end
      end

      lm_rows[lm_max_rows]:set({
        drawing = true,
        width = popup_width,
        label = "Unload all models",
      })
      lm_actions[lm_max_rows] = function()
        lm_popup.popup.hide()
        sbar.exec("/bin/zsh -lc '" .. lms_prefix .. "${LMS} unload --all'")
      end
    end)
  end)
end

local onepassword_popup = make_popup("onepassword", "1Password", "Quick Access")

onepassword_popup.add_action_row("Quick Access", function()
  onepassword_popup.popup.hide()
  sbar.exec("osascript -e 'tell application \"System Events\" to key code 49 using {command down, shift down}'")
end)

onepassword_popup.add_action_row("Open app", function()
  onepassword_popup.popup.hide()
  sbar.exec("open -a '1Password'")
end)

local qx_popup = make_popup("quantumultx", "Quantumult X", "Public IP info")

local qx_ip = qx_popup.add_row("Public IP", "...", { label_align = "right" })
local qx_location = qx_popup.add_row("Location", "...", { label_align = "right" })
local qx_isp = qx_popup.add_row("ISP", "...", { label_align = "right" })

local function trim_newline(s)
  return (s or ""):gsub("\r", ""):gsub("\n$", "")
end

local function update_ipinfo()
  qx_ip:set({ label = "..." })
  qx_location:set({ label = "..." })
  qx_isp:set({ label = "..." })

  sbar.exec("/bin/zsh -lc 'curl -m 2 -s https://ipinfo.io/ip'", function(result)
    local ip = trim_newline(result)
    if ip == "" then ip = "Unknown" end
    qx_ip:set({ label = ip })
  end)
  sbar.exec("/bin/zsh -lc 'curl -m 2 -s https://ipinfo.io/city'", function(city)
    city = trim_newline(city)
    sbar.exec("/bin/zsh -lc 'curl -m 2 -s https://ipinfo.io/country'", function(country)
      country = trim_newline(country)
      local loc = (city ~= "" and country ~= "") and (city .. ", " .. country) or (city ~= "" and city or (country ~= "" and country or "Unknown"))
      qx_location:set({ label = loc })
    end)
  end)
  sbar.exec("/bin/zsh -lc 'curl -m 2 -s https://ipinfo.io/org'", function(org)
    org = trim_newline(org)
    if org == "" then org = "Unknown" end
    qx_isp:set({ label = org })
  end)
end

qx_popup.add_action_row("Open app", function()
  qx_popup.popup.hide()
  sbar.exec("open -a 'Quantumult X'")
end)

qx_popup.add_action_row("Refresh info", function()
  update_ipinfo()
end)

local synergy_popup = make_popup("synergy", "Synergy", "Status")

local synergy_main = synergy_popup.add_row("Main", "-", { label_align = "right" })
local synergy_server = synergy_popup.add_row("Server", "-", { label_align = "right" })
local synergy_client = synergy_popup.add_row("Client", "-", { label_align = "right" })

local check_cmd = [=[/bin/zsh -lc '
main="STOPPED"
if /usr/bin/osascript -e "tell application \"System Events\" to (exists process \"Synergy\")" | grep -qi true; then main="RUNNING"; fi
server="STOPPED"; if /usr/bin/pgrep -f -q "(^|/)synergy-server([[:space:]]|$)"; then server="RUNNING"; fi
client="STOPPED"; if /usr/bin/pgrep -f -q "(^|/)synergy-client([[:space:]]|$)"; then client="RUNNING"; fi
echo "main:$main"
echo "server:$server"
echo "client:$client"
']=]

local function populate_synergy()
  sbar.exec(check_cmd, function(out)
    local o = out or ""
    local main = o:match("main:(%w+)") or "STOPPED"
    local server = o:match("server:(%w+)") or "STOPPED"
    local client = o:match("client:(%w+)") or "STOPPED"
    synergy_main:set({ label = main })
    synergy_server:set({ label = server })
    synergy_client:set({ label = client })
  end)
end

local open_main_cmd = [=[/bin/zsh -lc '
if ! /usr/bin/osascript -e "tell application \"System Events\" to (exists process \"Synergy\")" | grep -qi true; then
  open -ga "Synergy"
  sleep 1
fi

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

synergy_popup.add_action_row("Open app", function()
  synergy_popup.popup.hide()
  sbar.exec(open_main_cmd)
end)

local tm_popup = make_popup("time_machine", "Time Machine", "Backup status")

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
    "}",
  }
  return build_jxa_cmd(js_lines, shell_cmd)
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

local tm_status_row = tm_popup.add_row("Status", "-", { label_align = "right" })
local tm_latest_row = tm_popup.add_row("Latest", "-", { label_align = "right" })

local function populate_tm_details()
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
    if status == "" then status = "-" end
    tm_status_row:set({ label = status })
  end)

  local function set_latest(text)
    text = trim_newline(text)
    if text == "" then text = "-" end
    tm_latest_row:set({ label = text })
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
      set_latest(first_line ~= "" and first_line or "-")
    end)
  end)
end

tm_popup.add_action_row("Open settings", function()
  tm_popup.popup.hide()
  sbar.exec("open 'x-apple.systempreferences:com.apple.TimeMachine-Settings.extension'")
end)

tm_popup.add_action_row("Start backup", function()
  exec(jxa_admin_cmd("tmutil startbackup"), function(_)
    sbar.delay(0.5, function() populate_tm_details() end)
  end)
end)

tm_popup.add_action_row("Stop backup", function()
  exec(jxa_admin_cmd("tmutil stopbackup"), function(_)
    sbar.delay(0.5, function() populate_tm_details() end)
  end)
end)

tm_popup.add_action_row("Open destination", function()
  local cmd = [[/bin/zsh -lc 'tmutil destinationinfo 2>/dev/null | grep "^URL" | head -n1 | cut -d: -f2- | sed -E "s/^ +//; s/ +$//"']]
  exec(cmd, function(url)
    url = (url or ""):gsub("\n$", "")
    if url ~= "" then
      tm_popup.popup.hide()
      exec("/bin/zsh -lc 'open \"" .. url .. "\"'", function(_) end)
    else
      tm_popup.popup.hide()
      exec("/bin/zsh -lc 'open " ..
        "\"x-apple.systempreferences:com.apple.TimeMachine-Settings.extension\" || open -a \"Time Machine\"'", function(_) end)
    end
  end)
end)

tm_popup.add_action_row("Open Time Machine", function()
  tm_popup.popup.hide()
  exec("/bin/zsh -lc 'open -a \"Time Machine\"'", function(_) end)
end)

local ubuntu_popup = make_popup("ubuntu", "Ubuntu", "Remote metrics")

local target_path = os.getenv("HOME") .. "/.config/sketchybar/ubuntu_target"
local ubuntu_enabled = false
local ssh_target = ""
local f = io.open(target_path, "r")
if f then
  ssh_target = (f:read("*l") or ""):gsub("%s+$", "")
  f:close()
  if ssh_target ~= "" then
    ubuntu_enabled = true
  end
end

local function short_host(user_at_host)
  local host = user_at_host:match("@([^@]+)$") or user_at_host
  host = host:gsub("^%s+", ""):gsub("%s+$", "")
  return host:match("^[^.]+") or host
end

local function shorten_gpu_name(name)
  if not name or name == "" then return "GPU" end
  name = name
    :gsub("^NVIDIA%s+GeForce%s+RTX%s+", "")
    :gsub("^NVIDIA%s+GeForce%s+", "")
    :gsub("^NVIDIA%s+", "")
    :gsub("^GeForce%s+", "")
    :gsub("%s+Graphics$", "")
  local tail = name:match("(%d+%s*[A-Za-z]?)%s*$")
  if tail then name = tail end
  name = name:gsub("(%d+)%s*([A-Za-z])$", "%1%2")
  return name
end

local load_item
local cpu_item
local mem_item
local home_item
local nvme_rows
local gpu_rows
local update_ubuntu

if ubuntu_enabled then
  ubuntu_popup.popup.set_meta("Host: " .. short_host(ssh_target))

  ubuntu_popup.add_action_row("Refresh metrics", function()
    if update_ubuntu then update_ubuntu() end
  end)

  load_item = ubuntu_popup.add_row("Load", "-", { label_align = "right" })
  cpu_item = ubuntu_popup.add_row("CPU", "-", { label_align = "right" })
  mem_item = ubuntu_popup.add_row("Memory", "-", { label_align = "right" })
  home_item = ubuntu_popup.add_row("/home", "-", { label_align = "right" })

  nvme_rows = {}
  for i = 1, 8 do
    nvme_rows[i] = ubuntu_popup.add_row("", "", { drawing = false, label_align = "right" })
  end

  gpu_rows = {}
  for i = 1, 6 do
    gpu_rows[i] = ubuntu_popup.add_row("", "", { drawing = false, label_align = "right" })
  end
else
  ubuntu_popup.popup.set_meta("No target configured")
  ubuntu_popup.add_row("Status", "No target configured")
end

local function parse_ssh_output(out)
  local lines = {}
  for line in tostring(out or ""):gmatch("[^\n]+") do lines[#lines+1] = line end

  local gpus = {}
  local loads = nil
  local cpu_use = nil
  local mem_used, mem_total = nil, nil
  local tctl = nil
  local nvmes = {}
  local home_total_raw, home_used_raw = nil, nil
  local current_nvme_id = nil

  for _, line in ipairs(lines) do
    local name, util, temp, memu, memt = line:match("^(.-),%s*([%d%.]+),%s*([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)%s*$")
    if name and util and temp and memu and memt then
      gpus[#gpus+1] = {
        name = name:gsub("^%s+", ""):gsub("%s+$", ""),
        util = tonumber(util),
        temp = tonumber(temp),
        mem_used_mib = tonumber(memu),
        mem_total_mib = tonumber(memt),
      }
    else
      local nvme_id = line:match("^nvme%-pci%-(%d+)")
      if nvme_id then
        current_nvme_id = tonumber(nvme_id)
      else
        local nv_t = line:match("^Composite:%s*%+([%d%.]+)°C")
        if nv_t and current_nvme_id then
          nvmes[#nvmes+1] = { id = current_nvme_id, temp = tonumber(nv_t) }
          current_nvme_id = nil
        end
      end

      if not loads then
        local l1, l5, l15 = line:match("load average:%s*([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)")
        if l1 and l5 and l15 then
          loads = string.format("%s / %s / %s", l1, l5, l15)
        end
      end
      if not cpu_use then
        local idle = line:match("([%d%.]+)%s*id")
        if idle then
          local idle_n = tonumber(idle) or 0
          local use = 100 - idle_n
          if use < 0 then use = 0 end
          if use > 100 then use = 100 end
          cpu_use = string.format("%.1f%%", use)
        end
      end
      if not mem_used then
        local total, free, used, cache = line:match("MiB Mem%s*:%s*([%d%.]+)%s*total,%s*([%d%.]+)%s*free,%s*([%d%.]+)%s*used,%s*([%d%.]+)%s*buff/cache")
        if total and used then
          mem_total = tonumber(total)
          mem_used = tonumber(used)
        end
      end
      if not tctl then
        local t = line:match("Tctl:%s*%+([%d%.]+)°C")
        if t then tctl = tonumber(t) end
      end
      if (not home_total_raw) or (not home_used_raw) then
        local size, used, mount = line:match("^%S+%s+(%S+)%s+(%S+)%s+%S+%s+%S+%s+(%S+)%s*$")
        if size and used and mount == "/home" then
          home_total_raw = size
          home_used_raw = used
        end
      end
    end
  end

  return {
    gpus = gpus,
    loads = loads,
    cpu_use = cpu_use,
    mem_used = mem_used,
    mem_total = mem_total,
    tctl = tctl,
    nvmes = nvmes,
    home_total_raw = home_total_raw,
    home_used_raw = home_used_raw,
  }
end

local function apply_state(st)
  if not (load_item and cpu_item and mem_item and home_item and nvme_rows and gpu_rows) then return end

  for i = 1, #gpu_rows do
    local row = gpu_rows[i]
    if i <= #st.gpus then
      local g = st.gpus[i]
      local name = shorten_gpu_name(g.name)
      local function gpu_label()
        local used_gb = math.floor((g.mem_used_mib or 0) / 1024 + 0.5)
        return string.format("%d%%, %dC, %dG", math.floor(g.util or 0), math.floor(g.temp or 0), used_gb)
      end
      if g.name and g.name ~= "" then
        row:set({
          icon = { string = name .. ":" },
          label = gpu_label(),
          drawing = true,
        })
      else
        row:set({
          icon = { string = "GPU:" },
          label = gpu_label(),
          drawing = true,
        })
      end
    else
      row:set({ icon = { string = "" }, label = "", drawing = false })
    end
  end

  if st.cpu_use or st.tctl then
    local cpu_bits = {}
    if st.cpu_use then cpu_bits[#cpu_bits+1] = st.cpu_use end
    if st.tctl then cpu_bits[#cpu_bits+1] = string.format("%dC", math.floor(st.tctl)) end
    cpu_item:set({ label = table.concat(cpu_bits, ", ") })
  else
    cpu_item:set({ label = "-" })
  end

  if st.mem_used and st.mem_total then
    local used_gb = math.floor((st.mem_used or 0) / 1024 + 0.5)
    local total_gb = math.floor((st.mem_total or 0) / 1024 + 0.5)
    mem_item:set({ label = string.format("%dG / %dG", used_gb, total_gb) })
  else
    mem_item:set({ label = "-" })
  end

  local load_s = st.loads or "-"
  load_item:set({ label = load_s })

  if st.home_total_raw and st.home_used_raw then
    home_item:set({ label = string.format("%s / %s", st.home_used_raw, st.home_total_raw) })
  else
    home_item:set({ label = "-" })
  end

  if st.nvmes and #st.nvmes > 0 then
    local has_name = st.nvmes[1].name ~= nil
    if not has_name then
      table.sort(st.nvmes, function(a, b) return (a.id or 0) < (b.id or 0) end)
    end
    for i = 1, #nvme_rows do
      local row = nvme_rows[i]
      if i <= #st.nvmes then
        local n = st.nvmes[i]
        local name = n.name or (n.id and ("NVMe" .. tostring(n.id))) or ("NVMe" .. tostring(i))
        row:set({
          icon = { string = name .. ":" },
          label = string.format("%dC", math.floor(n.temp or 0)),
          drawing = true,
        })
      else
        row:set({ icon = { string = "" }, label = "", drawing = false })
      end
    end
  else
    for i = 1, #nvme_rows do
      nvme_rows[i]:set({ icon = { string = "" }, label = "", drawing = false })
    end
  end
end

local function sh_quote_single(s)
  return "'" .. tostring(s):gsub("'", "'\"'\"'") .. "'"
end

local function build_ssh()
  local remote_cmd = [[nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits && top -bn1 | head -5 && sensors && df -h /home | tail -1]]
  local ssh_inner = "ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=accept-new " .. ssh_target .. " " .. sh_quote_single(remote_cmd)
  local cmd = "/bin/zsh -lc " .. sh_quote_single(ssh_inner)
  return cmd
end

local function set_ubuntu_error(text)
  if not ubuntu_enabled then return end
  local msg = text or "Unavailable"
  load_item:set({ label = msg })
  cpu_item:set({ label = msg })
  mem_item:set({ label = msg })
  home_item:set({ label = msg })
  for i = 1, #nvme_rows do
    nvme_rows[i]:set({ icon = { string = "" }, label = "", drawing = false })
  end
  for i = 1, #gpu_rows do
    gpu_rows[i]:set({ icon = { string = "" }, label = "", drawing = false })
  end
end

if ubuntu_enabled then
  update_ubuntu = function()
    sbar.exec(build_ssh(), function(out, _)
      if not out or out == "" then
        set_ubuntu_error("Unreachable")
        return
      end
      local st = parse_ssh_output(out)
      apply_state(st)
    end)
  end
end

local wechat_popup = make_popup("wechat", "WeChat", "Unread badge")

local wechat_unread = wechat_popup.add_row("Unread", "-", { label_align = "right" })

wechat_popup.add_action_row("Open app", function()
  wechat_popup.popup.hide()
  sbar.exec("/bin/zsh -lc 'open -a WeChat || open -b com.tencent.xinWeChat'")
end)

local clipboard_icon = icons.clipboard
local dictionary_icon = icons.translate
local lm_icon, lm_font = app_icon("LM Studio", icons.lm_studio, 16.0)
local onepassword_icon, onepassword_font = app_icon("1Password", icons.onepassword, 16.0)
local qx_icon, qx_font = app_icon("Quantumult X", icons.quantumultx, 16.0)
local synergy_icon = icons.synergy
local time_machine_icon = icons.time_machine
local ubuntu_icon = icons.ubuntu
local wechat_icon, wechat_font = app_icon("WeChat", icons.clipboard, 19.0)

local icon_font = {
  family = settings.font.icons,
  style = settings.font.style_map["Regular"],
  size = 16.0,
}

add_icon_item("clipboard", clipboard_icon, icon_font, clipboard_popup.popup, nil)
add_icon_item("dictionary", dictionary_icon, icon_font, dictionary_popup.popup, nil)
add_icon_item("lm_studio", lm_icon, lm_font, lm_popup.popup, populate_lm_studio)
add_icon_item("onepassword", onepassword_icon, onepassword_font, onepassword_popup.popup, nil)
add_icon_item("quantumultx", qx_icon, qx_font, qx_popup.popup, update_ipinfo)
add_icon_item("synergy", synergy_icon, icon_font, synergy_popup.popup, populate_synergy)
add_icon_item("time_machine", time_machine_icon, icon_font, tm_popup.popup, populate_tm_details)
add_icon_item("ubuntu", ubuntu_icon, icon_font, ubuntu_popup.popup, function()
  if update_ubuntu then update_ubuntu() end
end)

local wechat_icon_color = colors.white
local wechat_item
local update_wechat_badge

wechat_item = add_icon_item("wechat", wechat_icon, wechat_font, wechat_popup.popup, function()
  if update_wechat_badge then update_wechat_badge() end
end, {
  label = {
    drawing = true,
    string = "",
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
    },
    color = colors.white,
  },
  icon_color = function()
    return wechat_icon_color
  end,
})

local function jxa_dock_badge_for(app_name)
  local js_lines = {
    "function run(argv) {",
    "  var app = Application.currentApplication();",
    "  app.includeStandardAdditions = true;",
    "  try {",
    "    var se = Application('System Events');",
    "    var dock = se.processes.byName('Dock');",
    "    var list = dock.lists[0];",
    "    var tiles = list.uiElements();",
    "    for (var i = 0; i < tiles.length; i++) {",
    "      var t = tiles[i];",
    "      var nm = '';",
    "      try { nm = String(t.name()); } catch (e) {}",
    "      if (nm.indexOf('WeChat') !== -1 || nm.indexOf('\\u5fae\\u4fe1') !== -1) {",
    "        try {",
    "          var v = t.attributes.byName('AXStatusLabel').value();",
    "          var s = String(v);",
    "          var mm = s.match(/\\d+/);",
    "          if (mm) return mm[0];",
    "        } catch (e) {}",
    "      }",
    "    }",
    "  } catch (e) {}",
    "  return '';",
    "}",
  }
  local parts = {}
  for _, line in ipairs(js_lines) do
    parts[#parts+1] = "-e " .. string.format("%q", line)
  end
  return "/usr/bin/osascript -l JavaScript " .. table.concat(parts, " ") .. " -- " .. string.format("%q", app_name)
end

update_wechat_badge = function()
  local cmd = jxa_dock_badge_for("WeChat")
  sbar.exec(cmd, function(out)
    local badge = (out or ""):gsub("\n$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if badge == "" then
      wechat_icon_color = colors.white
      wechat_item:set({
        label = { drawing = false, string = "" },
        icon = { color = wechat_icon_color },
      })
      wechat_unread:set({ label = { string = "None", color = colors.white } })
    else
      wechat_icon_color = colors.green
      wechat_item:set({
        label = { drawing = true, string = badge },
        icon = { color = wechat_icon_color },
      })
      wechat_unread:set({ label = { string = badge, color = colors.green } })
    end
  end)
end

update_wechat_badge()

wechat_item:set({ update_freq = 10 })
wechat_item:subscribe("routine", function(_)
  update_wechat_badge()
end)

wechat_item:subscribe({ "front_app_switched", "system_woke" }, function(_)
  update_wechat_badge()
end)
