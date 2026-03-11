local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

-- Battery control popup with slider, graph, and interactive controls
local config_path = os.getenv("HOME") .. "/.config/sketchybar"
local state_file = config_path .. "/states/battery_control.lua"
local battery_helper_path = config_path .. "/helpers/battery_info/bin/battery_info"
local battery_control_path = config_path .. "/helpers/battery_control/bin/battery_control"

-- State caching for main widget
local last_charge = nil
local last_charging = nil
local last_icon = nil
local last_color = nil

-- Maintain state (persisted)
local maintain_state = {
  enabled = false,
  target = 80,
  history = {},  -- Battery percentage history (max 144 points = 24h @ 10min)
}

-- Load persisted state
local function load_state()
  local f = io.open(state_file, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  local fn = load("return " .. content)
  if fn then
    local ok, loaded = pcall(fn)
    if ok and type(loaded) == "table" then
      if loaded.target then maintain_state.target = loaded.target end
      if loaded.enabled ~= nil then maintain_state.enabled = loaded.enabled end
      if loaded.history then maintain_state.history = loaded.history end
    end
  end
end

-- Serialize table to Lua code
local function serialize(t, indent)
  indent = indent or ""
  local parts = {}
  parts[#parts + 1] = "{"
  local next_indent = indent .. "  "
  for k, v in pairs(t) do
    local key_str
    if type(k) == "number" then
      key_str = ""
    else
      key_str = k .. " = "
    end
    local val_str
    if type(v) == "table" then
      val_str = serialize(v, next_indent)
    elseif type(v) == "string" then
      val_str = string.format("%q", v)
    elseif type(v) == "boolean" then
      val_str = v and "true" or "false"
    else
      val_str = tostring(v)
    end
    parts[#parts + 1] = next_indent .. key_str .. val_str .. ","
  end
  parts[#parts + 1] = indent .. "}"
  return table.concat(parts, "\n")
end

-- Save state to file
local function save_state()
  local f = io.open(state_file, "w")
  if not f then return end
  f:write(serialize(maintain_state))
  f:close()
end

-- Record battery percentage to history (called every 10 minutes)
local function record_history(percent)
  table.insert(maintain_state.history, percent)
  -- Keep max 144 points (24 hours at 10-minute intervals)
  while #maintain_state.history > 144 do
    table.remove(maintain_state.history, 1)
  end
  save_state()
end

load_state()

local function file_exists(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

local function fetch_battery_info(callback)
  if not file_exists(battery_helper_path) then
    if callback then callback(nil, 1) end
    return
  end
  sbar.exec(battery_helper_path, function(info, exit_code)
    if callback then callback(info, exit_code) end
  end)
end

-- Fetch control status from battery_control helper
local function fetch_control_status(callback)
  if not file_exists(battery_control_path) then
    if callback then callback(nil, 1) end
    return
  end
  sbar.exec("sudo " .. battery_control_path .. " status", function(info, exit_code)
    if callback then callback(info, exit_code) end
  end)
end

-- Enable charging
local function enable_charging(callback)
  sbar.exec("sudo " .. battery_control_path .. " enable", function(_, exit_code)
    if callback then callback(exit_code == 0) end
  end)
end

-- Disable charging
local function disable_charging(callback)
  sbar.exec("sudo " .. battery_control_path .. " disable", function(_, exit_code)
    if callback then callback(exit_code == 0) end
  end)
end

-- Enable adapter (normal power from charger, disable forced discharge)
-- Note: battery_control "adapter off" = disable_discharging (matches battery.sh)
local function enable_adapter(callback)
  sbar.exec("sudo " .. battery_control_path .. " adapter off", function(_, exit_code)
    if callback then callback(exit_code == 0) end
  end)
end

-- Disable adapter (force discharge even when plugged in)
-- Note: battery_control "adapter on" = enable_discharging (matches battery.sh)
local function disable_adapter(callback)
  sbar.exec("sudo " .. battery_control_path .. " adapter on", function(_, exit_code)
    if callback then callback(exit_code == 0) end
  end)
end

local BATTERY_UPDATE_FREQ_IDLE = 600
local BATTERY_UPDATE_FREQ_MAINTAIN = 60
local HISTORY_RECORD_INTERVAL_SEC = 600

-- Main battery widget
local battery = sbar.add("item", "widgets.battery", {
  position = "right",
  icon = {
    font = {
      style = settings.font.style_map["Regular"],
      size = 15.0,
    }
  },
  label = {
    font = { family = settings.font.numbers },
    width = 32,
    padding_left = 2,
    padding_right = 6,
  },
  padding_left = 0,
  padding_right = 0,
  update_freq = maintain_state.enabled and BATTERY_UPDATE_FREQ_MAINTAIN or BATTERY_UPDATE_FREQ_IDLE,
})

local function sync_battery_update_freq()
  local freq = maintain_state.enabled and BATTERY_UPDATE_FREQ_MAINTAIN or BATTERY_UPDATE_FREQ_IDLE
  battery:set({ update_freq = freq })
end

-- Popup setup
local popup_width = 420
local battery_popup = center_popup.create("battery.popup", {
  width = popup_width,
  height = 780,
  popup_height = 26,
  title = "Battery",
  meta = "",
  auto_hide = false,
})
battery_popup.meta_item:set({ drawing = false })
battery_popup.body_item:set({ drawing = false })

local popup_pos = battery_popup.position
local name_width = 160
local value_width = popup_width - name_width

-- Helper to add info rows
local function add_row(key, title)
  return sbar.add("item", "battery.popup." .. key, {
    position = popup_pos,
    width = popup_width,
    icon = {
      align = "left",
      string = title,
      width = name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 12.0 },
    },
    label = {
      align = "right",
      string = "-",
      width = value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 12.0 },
    },
    background = { drawing = false },
  })
end

-- Helper to add control rows (clickable)
local function add_control_row(key, title, initial_value)
  local row = sbar.add("item", "battery.popup.ctrl." .. key, {
    position = popup_pos,
    width = popup_width,
    icon = {
      align = "left",
      string = title,
      width = name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 12.0 },
    },
    label = {
      align = "right",
      string = initial_value .. " [toggle]",
      width = value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 12.0 },
      color = colors.blue,
    },
    background = { drawing = false },
  })
  return row
end

-- === POPUP CONTENT ===

-- Current status section
battery_popup.add_section("status", "STATUS")

local row_status = add_row("status", "Status")
local row_percent = add_row("percent", "Charge")
local row_power = add_row("power", "Power source")
local row_time = add_row("time", "Time remaining")

-- Power controls section
battery_popup.add_section("controls", "POWER CONTROLS")

local row_charging = add_control_row("charging", "Charging", "Enabled")
local row_adapter = add_control_row("adapter", "Adapter", "Enabled")

-- Charge limit section (slider + maintain toggle)
battery_popup.add_section("limit", "CHARGE LIMIT")

local maintain_slider = battery_popup.add_slider("maintain", {
  highlight_color = colors.green,
  percentage = maintain_state.target,
})

local row_maintain_target = add_row("maintain_target", "Target")
row_maintain_target:set({ label = { string = maintain_state.target .. "%" } })

local row_maintain = add_control_row("maintain", "Auto Maintain", maintain_state.enabled and "Active" or "Off")

-- Battery details section
battery_popup.add_section("details", "BATTERY DETAILS")

local row_health = add_row("health", "Health")
local row_cycles = add_row("cycles", "Cycle count")
local row_capacity = add_row("capacity", "Capacity")
local row_design = add_row("design", "Design / Nominal")
local row_temp = add_row("temp", "Temperature")

-- Electrical section
battery_popup.add_section("electrical", "ELECTRICAL")

local row_electrical = add_row("voltage_current", "Voltage / Current")
local row_power_draw = add_row("power_draw", "Power draw")
local row_cells = add_row("cells", "Cell voltages")

-- Advanced section
battery_popup.add_section("advanced", "ADVANCED")

local row_soc = add_row("soc", "SoC (smart)")
local row_pack = add_row("pack", "Pack reserve")
local row_charger = add_row("charger", "Charger")
local row_system = add_row("system", "System input")
local row_adapter_info = add_row("adapter_info", "Adapter info")
local row_device = add_row("device", "Device / FW")
local row_flags = add_row("flags", "Flags")
local row_serial = add_row("serial", "Serial")

battery_popup.add_close_row({ label = "close x" })

-- Formatting helpers
local function format_minutes(min)
  local n = tonumber(min)
  if not n or n <= 0 then return "-" end
  local h = math.floor(n / 60)
  local m = n % 60
  if h > 0 then
    return string.format("%dh %02dm", h, m)
  end
  return string.format("%dm", m)
end

local function format_voltage(mv)
  local n = tonumber(mv)
  if not n then return "-" end
  return string.format("%.2f V", n / 1000.0)
end

local function format_current(ma)
  local n = tonumber(ma)
  if n == nil then return "-" end
  return string.format("%d mA", n)
end

local function format_watts(w)
  local n = tonumber(w)
  if n == nil then return "-" end
  return string.format("%.1fW", n)
end

local function format_temp(c)
  local n = tonumber(c)
  if n == nil then return "-" end
  return string.format("%.1f°C", n)
end

local function format_adapter(info)
  if type(info) ~= "table" then return "-" end
  local watts = tonumber(info.adapter_watts)
  local desc = info.adapter_desc and tostring(info.adapter_desc) or ""
  local v = tonumber(info.adapter_voltage_mv)
  local a = tonumber(info.adapter_current_ma)
  local parts = {}
  if watts then parts[#parts + 1] = string.format("%dW", watts) end
  if desc ~= "" then parts[#parts + 1] = desc end
  if v then parts[#parts + 1] = string.format("%.1fV", v / 1000.0) end
  if a then parts[#parts + 1] = string.format("%dmA", a) end
  if #parts == 0 then return "-" end
  return table.concat(parts, " ")
end

local function format_cells(info)
  if type(info) ~= "table" then return "-" end
  local cells = info.cell_voltage_mv
  if type(cells) ~= "table" or #cells == 0 then return "-" end
  local parts = {}
  for i, v in ipairs(cells) do
    parts[i] = tostring(v)
  end
  local delta = tonumber(info.cell_voltage_delta_mv)
  if delta then
    return string.format("%s mV (Δ%d)", table.concat(parts, "/"), delta)
  end
  return string.format("%s mV", table.concat(parts, "/"))
end

local function guess_not_charging_reason(info, n)
  if not n or n == 0 then return nil end
  local power = tostring(info.power_source or "")
  local percent = tonumber(info.percent)
  local is_charging = info.is_charging == true
  local is_charged = info.is_charged == true or info.fully_charged == true
  local charger_current = tonumber(info.charger_current_ma)
  local temp_c = tonumber(info.temperature_c)

  if power == "AC" and not is_charging and (charger_current == nil or charger_current == 0) then
    if percent and percent >= 78 and percent <= 85 then
      return "hold-at-80%"
    end
    if is_charged or (percent and percent >= 95) then
      return "full"
    end
  end
  if temp_c and temp_c >= 45.0 then
    return "thermal"
  end
  return nil
end

local function format_reason_mask(info, value, prefix)
  local n = tonumber(value)
  if not n then return nil end
  if n == 0 then return nil end

  local bits = {}
  for i = 0, 62 do
    local bit = 1 << i
    if bit == 0 then break end
    if (n & bit) ~= 0 then
      bits[#bits + 1] = tostring(i)
    end
  end

  local hex = string.format("0x%08X", n & 0xffffffff)
  local bit_str = (#bits == 1) and ("b" .. bits[1]) or ("b[" .. table.concat(bits, ",") .. "]")
  local raw = hex .. "/" .. bit_str

  if prefix == "nr" then
    local hint = guess_not_charging_reason(info, n)
    if hint then
      if raw == "0x01000000/b24" then
        return prefix .. "=" .. hint
      end
      return prefix .. "=" .. hint .. " " .. raw
    end
  end
  return prefix .. "=" .. raw
end

local function format_charger_basic(info)
  if type(info) ~= "table" then return "-" end
  local v = tonumber(info.charger_voltage_mv)
  local c = tonumber(info.charger_current_ma)
  local id = tonumber(info.charger_id)
  local parts = {}
  if v then parts[#parts + 1] = string.format("%.2fV", v / 1000.0) end
  if c then parts[#parts + 1] = string.format("%dmA", c) end
  if id then parts[#parts + 1] = string.format("id=%d", id) end
  if #parts == 0 then return "-" end
  return table.concat(parts, " ")
end

local function format_charge_reason(info)
  if type(info) ~= "table" then return "-" end
  local nr = format_reason_mask(info, info.charger_not_charging_reason, "nr")
  local slow = format_reason_mask(info, info.charger_slow_charging_reason, "slow")
  local inh = format_reason_mask(info, info.charger_inhibit_reason, "inh")
  local parts = {}
  if nr then parts[#parts + 1] = nr end
  if slow then parts[#parts + 1] = slow end
  if inh then parts[#parts + 1] = inh end
  if #parts == 0 then return "-" end
  return table.concat(parts, " ")
end

local function ellipsize(text, max_chars)
  if type(text) ~= "string" then return "" end
  local max = tonumber(max_chars) or 0
  if max <= 0 then return text end
  if #text <= max then return text end
  if max <= 1 then return "…" end
  return text:sub(1, max - 1) .. "…"
end

local function format_system(info)
  if type(info) ~= "table" then return "-" end
  local v = tonumber(info.telemetry_system_voltage_in_mv)
  local a = tonumber(info.telemetry_system_current_in_ma)
  local w = tonumber(info.telemetry_system_power_in_w)
  local load = tonumber(info.telemetry_system_load)
  local parts = {}
  if v then parts[#parts + 1] = string.format("%.1fV", v / 1000.0) end
  if a then parts[#parts + 1] = string.format("%dmA", a) end
  if w then parts[#parts + 1] = format_watts(w) end
  if load then parts[#parts + 1] = string.format("load=%d", load) end
  if #parts == 0 then return "-" end
  return table.concat(parts, " ")
end

local function format_device(info)
  if type(info) ~= "table" then return "-" end
  local name = info.device_name and tostring(info.device_name) or ""
  local fw = tonumber(info.gas_gauge_fw)
  if name == "" and not fw then return "-" end
  if fw then
    if name ~= "" then return string.format("%s (fw %d)", name, fw) end
    return string.format("fw %d", fw)
  end
  return name
end

local function format_flags(info)
  if type(info) ~= "table" then return "-" end
  local parts = {}
  local function b(key, short)
    local v = info[key]
    if v == nil then return end
    parts[#parts + 1] = string.format("%s=%s", short, v and "1" or "0")
  end
  b("critical", "crit")
  b("battery_installed", "inst")
  b("external_connected", "ext")
  b("external_charge_capable", "cap")
  b("fully_charged", "full")
  local fail = tonumber(info.permanent_failure_status)
  if fail ~= nil then parts[#parts + 1] = string.format("fail=%d", fail) end
  if #parts == 0 then return "-" end
  return table.concat(parts, " ")
end

-- Update control row states
local function update_control_states()
  fetch_control_status(function(info, exit_code)
    if exit_code ~= 0 or type(info) ~= "table" then
      row_charging:set({ label = { string = "Unavailable" } })
      row_adapter:set({ label = { string = "Unavailable" } })
      return
    end

    local charging_str = info.charging_enabled and "Enabled" or "Disabled"
    local adapter_str = info.adapter_enabled and "Enabled" or "Disabled"
    row_charging:set({ label = { string = charging_str .. " [toggle]" } })
    row_adapter:set({ label = { string = adapter_str .. " [toggle]" } })
  end)

  local maintain_str = maintain_state.enabled and ("Active @ " .. maintain_state.target .. "%") or "Off"
  row_maintain:set({ label = { string = maintain_str .. " [toggle]" } })
end

-- Toggle charging
local function disable_maintain_for_manual_override()
  if not maintain_state.enabled then return end
  maintain_state.enabled = false
  save_state()
  sync_battery_update_freq()
  row_maintain:set({ label = { string = "Off [toggle]" } })
end

local check_and_maintain

local function toggle_charging()
  disable_maintain_for_manual_override()
  fetch_control_status(function(info, exit_code)
    if exit_code ~= 0 or type(info) ~= "table" then return end
    if info.charging_enabled then
      disable_charging(function() update_control_states() end)
    else
      enable_charging(function() update_control_states() end)
    end
  end)
end

-- Toggle adapter
local function toggle_adapter()
  disable_maintain_for_manual_override()
  fetch_control_status(function(info, exit_code)
    if exit_code ~= 0 or type(info) ~= "table" then return end
    if info.adapter_enabled then
      disable_adapter(function() update_control_states() end)
    else
      enable_adapter(function() update_control_states() end)
    end
  end)
end

-- Toggle maintain mode
local function toggle_maintain()
  maintain_state.enabled = not maintain_state.enabled
  save_state()
  sync_battery_update_freq()
  update_control_states()
  if maintain_state.enabled and check_and_maintain then
    check_and_maintain()
  end
end

-- Set maintain target
local function set_maintain_target(pct)
  maintain_state.target = pct
  row_maintain_target:set({ label = { string = pct .. "%" } })
  save_state()
  if maintain_state.enabled then
    update_control_states()
    if check_and_maintain then
      check_and_maintain()
    end
  end
end

-- Maintain loop - check and adjust charging
-- Logic follows battery.sh maintain_synchronous:
-- 1. At or above target: disable charging and force adapter on (normal power)
-- 2. Below (target - hysteresis): enable charging
-- 3. Between: keep current state (avoid rapid cycling)
local MAINTAIN_HYSTERESIS = 2  -- Same as battery.sh behavior

check_and_maintain = function()
  if not maintain_state.enabled then return end
  if not file_exists(battery_control_path) then return end

  fetch_battery_info(function(info, exit_code)
    if exit_code ~= 0 or type(info) ~= "table" then return end

    local percent = tonumber(info.percent)
    if not percent then return end

    -- Also check current charging state to avoid unnecessary commands
    fetch_control_status(function(ctrl_info, ctrl_exit)
      if ctrl_exit ~= 0 or type(ctrl_info) ~= "table" then return end

      local charging_enabled = ctrl_info.charging_enabled == true
      local adapter_enabled = ctrl_info.adapter_enabled == true

      if percent >= maintain_state.target then
        -- At or above target: enforce adapter on + charging off.
        local function stop_charging_with_adapter_on()
          if charging_enabled then
            disable_charging(function() end)
          end
        end

        if adapter_enabled then
          stop_charging_with_adapter_on()
        else
          enable_adapter(function()
            stop_charging_with_adapter_on()
          end)
        end
      elseif percent < maintain_state.target - MAINTAIN_HYSTERESIS then
        -- Below threshold: ensure adapter on and charging enabled.
        if not adapter_enabled then
          enable_adapter(function()
            if not charging_enabled then
              enable_charging(function() end)
            end
          end)
        elseif not charging_enabled then
          enable_charging(function() end)
        end
      end
      -- Between (target - hysteresis) and target: maintain current state
    end)
  end)
end

-- Subscribe slider to drag events
maintain_slider:subscribe("mouse.clicked", function(env)
  local pct = math.floor(tonumber(env.PERCENTAGE) or maintain_state.target)
  if pct < 20 then pct = 20 end
  if pct > 100 then pct = 100 end
  set_maintain_target(pct)
  maintain_slider:set({ slider = { percentage = pct } })
end)

-- Subscribe control rows to click events
row_charging:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" then return end
  toggle_charging()
end)

row_adapter:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" then return end
  toggle_adapter()
end)

row_maintain:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" then return end
  toggle_maintain()
end)

-- Main widget update
local function update_battery()
  if _G.SKETCHYBAR_SUSPENDED then return end

  fetch_battery_info(function(info, exit_code)
    if exit_code ~= 0 or type(info) ~= "table" then return end

    local charge = tonumber(info.percent)
    if not charge then return end
    local charge_i = math.floor(charge + 0.5)
    local charging = info.is_charging == true
    local charged = info.is_charged == true

    local color = colors.green
    local icon = icons.battery._0
    if charging then
      icon = icons.battery.charging
    elseif charged then
      icon = icons.battery._100
    else
      if charge > 80 then
        icon = icons.battery._100
      elseif charge > 60 then
        icon = icons.battery._75
      elseif charge > 40 then
        icon = icons.battery._50
      elseif charge > 20 then
        icon = icons.battery._25
        color = colors.orange
      else
        icon = icons.battery._0
        color = colors.red
      end
    end

    if last_charge == charge_i and last_charging == charging and last_icon == icon and last_color == color then
      return
    end
    last_charge = charge_i
    last_charging = charging
    last_icon = icon
    last_color = color

    battery:set({
      icon = { string = icon, color = color },
      label = { string = tostring(charge_i) },
    })
  end)
end

-- Routine update for maintain mode and history recording
local last_history_record_at = os.time()
local function routine_update()
  check_and_maintain()

  local now = os.time()
  if now - last_history_record_at < HISTORY_RECORD_INTERVAL_SEC then return end
  last_history_record_at = now

  fetch_battery_info(function(info, exit_code)
    if exit_code ~= 0 or type(info) ~= "table" then return end
    local percent = tonumber(info.percent)
    if percent then
      record_history(percent)
    end
  end)
end

battery:subscribe({ "forced", "routine", "power_source_change", "system_woke" }, function()
  update_battery()
  routine_update()
end)
update_battery()
if maintain_state.enabled then
  check_and_maintain()
end

-- Popup click handler
battery:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("/usr/bin/open 'x-apple.systempreferences:com.apple.preference.battery' >/dev/null 2>&1", function() end)
    return
  end
  if env.BUTTON ~= "left" then return end

  if battery_popup.is_showing() then
    battery_popup.hide()
    return
  end

  -- Set slider to current target
  maintain_slider:set({ slider = { percentage = maintain_state.target } })

  battery_popup.show(function()
    -- Update control states
    update_control_states()

    -- Fetch and display battery info
    row_status:set({ label = { string = "Loading…" } })
    fetch_battery_info(function(info, exit_code)
      if exit_code ~= 0 or type(info) ~= "table" then
        row_status:set({ label = { string = "Unavailable" } })
        return
      end

      local percent = tonumber(info.percent)
      local charging = info.is_charging == true
      local charged = info.is_charged == true
      local power = tostring(info.power_source or "-")

      local status = "Discharging"
      if power == "AC" and not charging and not charged then
        status = "Not charging"
      end
      if charging then status = "Charging" end
      if charged then status = "Charged" end

      local time_label = "-"
      if charging then
        time_label = format_minutes(info.time_to_full_min)
      else
        time_label = format_minutes(info.time_to_empty_min)
      end

      row_status:set({ label = { string = status } })
      row_percent:set({ label = { string = percent and (tostring(percent) .. "%") or "-" } })
      local adapter_watts = tonumber(info.adapter_watts)
      if adapter_watts then
        row_power:set({ label = { string = string.format("%s (%dW)", power, adapter_watts) } })
      else
        row_power:set({ label = { string = power } })
      end
      row_time:set({ label = { string = time_label } })
      local cycles = info.cycle_count and tostring(info.cycle_count) or "-"
      local design_cycles = tonumber(info.design_cycle_count)
      if design_cycles then
        cycles = string.format("%s / %d", cycles, design_cycles)
      end
      row_cycles:set({ label = { string = cycles } })

      local health = "-"
      local health_pct = tonumber(info.health_percent)
      if health_pct then
        health = string.format("%.0f%%", health_pct)
      elseif info.health and tostring(info.health) ~= "" then
        health = tostring(info.health)
      end
      row_health:set({ label = { string = health } })

      local cap_cur = tonumber(info.raw_current_capacity)
      local cap_max = tonumber(info.raw_max_capacity)
      if cap_cur and cap_max and cap_max > 0 then
        row_capacity:set({ label = { string = string.format("%d / %d mAh", cap_cur, cap_max) } })
      else
        row_capacity:set({ label = { string = "-" } })
      end

      local design_cap = tonumber(info.design_capacity)
      local nominal_cap = tonumber(info.nominal_capacity)
      if design_cap and nominal_cap then
        row_design:set({ label = { string = string.format("%d / %d mAh", design_cap, nominal_cap) } })
      elseif design_cap then
        row_design:set({ label = { string = string.format("%d mAh", design_cap) } })
      else
        row_design:set({ label = { string = "-" } })
      end

      row_temp:set({ label = { string = format_temp(info.temperature_c) } })
      local cur_ma = info.instant_amperage_ma ~= nil and info.instant_amperage_ma or info.amperage_ma
      row_electrical:set({ label = { string = string.format("%s / %s", format_voltage(info.voltage_mv), format_current(cur_ma)) } })

      local batt_w = format_watts(info.power_w)
      local sys_w = format_watts(info.telemetry_system_power_in_w)
      row_power_draw:set({ label = { string = string.format("%s / %s", batt_w, sys_w) } })

      row_cells:set({ label = { string = format_cells(info) } })

      local soc = tonumber(info.soc_percent)
      local dmin = tonumber(info.daily_min_soc)
      local dmax = tonumber(info.daily_max_soc)
      if soc and dmin and dmax then
        row_soc:set({ label = { string = string.format("%d%% (daily %d–%d)", soc, dmin, dmax) } })
      elseif soc then
        row_soc:set({ label = { string = string.format("%d%%", soc) } })
      else
        row_soc:set({ label = { string = "-" } })
      end

      local pack = tonumber(info.pack_reserve)
      if pack then
        row_pack:set({ label = { string = tostring(pack) } })
      else
        row_pack:set({ label = { string = "-" } })
      end

      local charger_line = format_charger_basic(info)
      local reason_line = format_charge_reason(info)
      if reason_line ~= "-" and reason_line ~= "" then
        charger_line = charger_line .. " " .. reason_line
      end
      row_charger:set({ label = { string = ellipsize(charger_line, 72) } })
      row_system:set({ label = { string = format_system(info) } })
      row_adapter_info:set({ label = { string = format_adapter(info) } })
      row_device:set({ label = { string = format_device(info) } })
      row_flags:set({ label = { string = format_flags(info) } })
      row_serial:set({ label = { string = info.serial and tostring(info.serial) or "-" } })
    end)
  end)
end)
