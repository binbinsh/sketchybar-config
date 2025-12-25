local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

-- Native event provider for network throughput ("network_update") on the primary
-- interface. This keeps the widget event-driven and avoids frequent shell polling.
sbar.exec("killall network_load >/dev/null 2>&1; $CONFIG_DIR/helpers/network_load/bin/network_load auto network_update 2.0")

-- Battery-style compact Wi‑Fi widget:
-- - Same compact feel as `battery.lua`, but with two stacked numbers:
--   top=upload, bottom=download (Mbps implied)
-- - No brackets (performance + simplicity)
-- - Event-driven + cached to avoid redundant set() calls
local last_connected = nil
local last_up_int = nil
local last_down_int = nil
local last_icon = nil
local last_icon_color = nil
local last_up_str = nil
local last_down_str = nil
local last_rate_color = nil

-- Allow overriding the interface used for the quick connectivity check.
-- If you are not using en0 for Wi‑Fi, export WIFI_INTERFACE accordingly.
local wifi_interface = os.getenv("WIFI_INTERFACE") or "en0"

local rate_label_width = 36
local rate_font = {
  family = settings.font.numbers,
  style = settings.font.style_map["Bold"],
  size = 9.0,
}

-- Add the rate labels FIRST so the Wi‑Fi icon item lands on the left on the right side.
-- Stack the labels by making the "up" item width=0 so it overlays the "down" item.
local wifi_up = sbar.add("item", "widgets.wifi.up", {
  position = "right",
  width = 0,
  padding_left = 0,
    padding_right = 0,
  icon = { drawing = false },
  label = {
    font = rate_font,
    width = rate_label_width,
    padding_left = 2,
    padding_right = 6,
    align = "left",
    string = "000",
    color = colors.white,
  },
  y_offset = 5,
  background = { drawing = false },
})

local wifi_down = sbar.add("item", "widgets.wifi.down", {
  position = "right",
  padding_left = 0,
    padding_right = 0,
  icon = { drawing = false },
  label = {
    font = rate_font,
    width = rate_label_width,
    padding_left = 2,
    padding_right = 6,
    align = "left",
    string = "000",
    color = colors.white,
  },
  y_offset = -5,
  background = { drawing = false },
})

local wifi = sbar.add("item", "widgets.wifi", {
  position = "right",
  icon = {
    padding_right = settings.paddings,
    font = {
      style = settings.font.style_map["Regular"],
      size = 15.0,
    },
  },
  label = { drawing = false },
  padding_left = 0,
  padding_right = 0,
  update_freq = 600,
  background = { drawing = false },
})

local function round_int(n)
  n = tonumber(n) or 0
  if n < 0 then n = 0 end
  return math.floor(n + 0.5)
end

local function format_widget_rate(mbps)
  local n = tonumber(mbps) or 0
  if n < 0 then n = 0 end
  local i = round_int(n)
  if i < 1000 then
    return string.format("%03d", i)
  end
  return tostring(i)
end

local function render_widget(connected, down_mbps, up_mbps)
  local icon = connected and icons.wifi.connected or icons.wifi.disconnected
  local down_i = round_int(down_mbps)
  local up_i = round_int(up_mbps)

  local icon_color = connected and colors.green or colors.red

  local up_str = connected and format_widget_rate(up_mbps) or "000"
  local down_str = connected and format_widget_rate(down_mbps) or "000"
  local rate_color = colors.white

  if last_connected == connected
    and last_down_int == down_i
    and last_up_int == up_i
    and last_icon == icon
    and last_icon_color == icon_color
    and last_up_str == up_str
    and last_down_str == down_str
    and last_rate_color == rate_color
  then
    return
  end

  last_connected = connected
  last_down_int = down_i
  last_up_int = up_i
  last_icon = icon
  last_icon_color = icon_color
  last_up_str = up_str
  last_down_str = down_str
  last_rate_color = rate_color

  wifi:set({ icon = { string = icon, color = icon_color } })
  wifi_up:set({ label = { string = up_str, color = rate_color } })
  wifi_down:set({ label = { string = down_str, color = rate_color } })
end

-- Popup (battery-style rows).
local popup_width = 420
local wifi_popup = center_popup.create("wifi.popup", {
  width = popup_width,
  height = 520,
  popup_height = 26,
  title = "Wi-Fi",
  meta = "",
  auto_hide = false,
})
wifi_popup.meta_item:set({ drawing = false })
wifi_popup.body_item:set({ drawing = false })

local popup_pos = wifi_popup.position
local name_width = 160
local value_width = popup_width - name_width

local function add_row(key, title, opts)
  opts = opts or {}
  return sbar.add("item", "wifi.popup." .. key, {
  position = popup_pos,
  width = popup_width,
    drawing = opts.drawing,
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
      max_chars = 64,
    },
    background = { drawing = false },
  })
end

local row_status = add_row("status", "Status")
local row_ssid = add_row("ssid", "SSID")
local row_hostname = add_row("hostname", "Hostname")
local row_interface = add_row("interface", "Interface", { drawing = false })
local row_adapter_mac = add_row("adapter_mac", "Adapter MAC", { drawing = false })
local row_ip = add_row("ip", "IP")
local row_mask = add_row("mask", "Subnet mask")
local row_router = add_row("router", "Router")
local row_download = add_row("download", "Download")
local row_upload = add_row("upload", "Upload")

-- Optional Wi‑Fi details (hidden until available).
local row_bssid = add_row("bssid", "BSSID", { drawing = false })
local row_phy = add_row("phy", "PHY Mode", { drawing = false })
local row_channel = add_row("channel", "Channel", { drawing = false })
local row_security = add_row("security", "Security", { drawing = false })
local row_interface_mode = add_row("interface_mode", "Interface Mode", { drawing = false })
local row_signal = add_row("signal", "S / N", { drawing = false })
local row_tx_rate = add_row("tx_rate", "Transmit Rate", { drawing = false })
local row_tx_power = add_row("tx_power", "Transmit Power", { drawing = false })
local row_mcs = add_row("mcs", "MCS Index", { drawing = false })
local row_cc = add_row("cc", "Country Code", { drawing = false })

wifi_popup.add_close_row({ label = "close x" })

local function set_opt_row(row, value)
  if not row then return end
  if value and value ~= "" then
    row:set({ drawing = true, label = { string = tostring(value) } })
  else
    row:set({ drawing = false })
  end
end

local function format_rate_row(mbps)
  local n = tonumber(mbps) or 0
  if n < 0 then n = 0 end
  return string.format("%d Mbps", round_int(n))
end

local current_connected = false
local current_down_mbps = 0
local current_up_mbps = 0

local function update_popup_rates(force)
  if not force and not wifi_popup.is_showing() then return end
  row_download:set({ label = { string = format_rate_row(current_down_mbps) } })
  row_upload:set({ label = { string = format_rate_row(current_up_mbps) } })
end

local function update_connection_state(force_popup)
  if _G.SKETCHYBAR_SUSPENDED then return end
  sbar.exec("/usr/sbin/ipconfig getifaddr " .. wifi_interface .. " 2>/dev/null", function(ip)
    ip = tostring(ip or ""):gsub("%s+$", "")
    current_connected = (ip ~= "")
    render_widget(current_connected, current_down_mbps, current_up_mbps)

    if force_popup or wifi_popup.is_showing() then
      row_status:set({ label = { string = current_connected and "Connected" or "Disconnected" } })
      row_ip:set({ label = { string = (ip ~= "") and ip or "-" } })
      update_popup_rates(true)
    end
  end)
end

wifi:subscribe({ "forced", "routine", "wifi_change", "system_woke" }, function(_)
  update_connection_state(false)
end)

wifi:subscribe("network_update", function(env)
  if _G.SKETCHYBAR_SUSPENDED then return end
  current_down_mbps = tonumber(env.download) or 0
  current_up_mbps = tonumber(env.upload) or 0
  render_widget(current_connected, current_down_mbps, current_up_mbps)
  update_popup_rates(false)
end)

-- Location permission gating (SSID may require it).
local location_checked = false
local function request_location_permission(done)
  if location_checked then
    if done then done() end
    return
  end
  location_checked = true
  sbar.exec("open -W \"$CONFIG_DIR/helpers/location/bin/SketchyBarLocationHelper.app\"", function()
    if done then done() end
  end)
end

local function apply_wifi_info(info)
  if type(info) ~= "table" then return end

  if info.interface and info.interface ~= "" then
    wifi_interface = tostring(info.interface)
    set_opt_row(row_interface, wifi_interface)
  else
    set_opt_row(row_interface, nil)
  end

  if info.ip and info.ip ~= "" then
    current_connected = true
  elseif info.ip == "" then
    current_connected = false
  end

  render_widget(current_connected, current_down_mbps, current_up_mbps)

  row_status:set({ label = { string = current_connected and "Connected" or "Disconnected" } })
  row_ssid:set({ label = { string = (info.ssid and info.ssid ~= "") and tostring(info.ssid) or "-" } })
  row_hostname:set({ label = { string = (info.hostname and info.hostname ~= "") and tostring(info.hostname) or "-" } })
  row_ip:set({ label = { string = (info.ip and info.ip ~= "") and tostring(info.ip) or "-" } })
  row_mask:set({ label = { string = (info.subnet_mask and info.subnet_mask ~= "") and tostring(info.subnet_mask) or "-" } })
  row_router:set({ label = { string = (info.router and info.router ~= "") and tostring(info.router) or "-" } })

  set_opt_row(row_adapter_mac, info.adapter_mac)
  set_opt_row(row_bssid, info.bssid)
  set_opt_row(row_phy, info.phy_mode)
  set_opt_row(row_channel, info.channel)
  set_opt_row(row_security, info.security)
  set_opt_row(row_interface_mode, info.interface_mode)
  set_opt_row(row_signal, info.signal_noise)
  set_opt_row(row_tx_rate, info.transmit_rate)
  set_opt_row(row_tx_power, info.transmit_power)
  set_opt_row(row_mcs, info.mcs_index)
  set_opt_row(row_cc, info.country_code)

  update_popup_rates(true)
end

local function fetch_wifi_info(after)
  sbar.exec("$CONFIG_DIR/helpers/network_info/bin/SketchyBarNetworkInfoHelper.app/Contents/MacOS/SketchyBarNetworkInfoHelper auto", function(info)
    apply_wifi_info(info)
    if after then after(info) end
  end)
end

local function populate_wifi_details()
  fetch_wifi_info(function(info)
    if info and info.ssid and info.ssid ~= "" then return end
    request_location_permission(function()
      fetch_wifi_info()
    end)
  end)
end

local function wifi_on_click(env)
  if env.BUTTON == "right" then
    sbar.exec("/usr/bin/open 'x-apple.systempreferences:com.apple.preference.network' >/dev/null 2>&1", function() end)
    return
  end
  if env.BUTTON ~= "left" then return end

  if wifi_popup.is_showing() then
    wifi_popup.hide()
    return
  end

  wifi_popup.show(function()
    -- Note: center_popup.show runs this callback BEFORE the popup is drawn.
    -- We still populate rows here so values are ready on first render.
    row_status:set({ label = { string = current_connected and "Connected" or "Disconnected" } })
    update_popup_rates(true)
    update_connection_state(true)
    populate_wifi_details()
  end)
end

wifi:subscribe("mouse.clicked", wifi_on_click)
wifi_up:subscribe("mouse.clicked", wifi_on_click)
wifi_down:subscribe("mouse.clicked", wifi_on_click)

-- Initial sync (best effort).
render_widget(false, 0, 0)
update_connection_state(false)
