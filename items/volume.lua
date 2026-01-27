local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local center_popup = require("center_popup")

-- Geek-style volume widget with draggable slider and detailed audio info

local function clamp_int(n, lo, hi)
  n = tonumber(n)
  if not n then return lo end
  if n < lo then return lo end
  if n > hi then return hi end
  return math.floor(n + 0.5)
end

local function icon_for_volume(volume, muted)
  if muted then return icons.volume._0 end
  if volume > 60 then return icons.volume._100 end
  if volume > 30 then return icons.volume._66 end
  if volume > 10 then return icons.volume._33 end
  if volume > 0 then return icons.volume._10 end
  return icons.volume._0
end

local function vol_to_db(vol)
  if vol <= 0 then return "-∞" end
  if vol >= 100 then return "0" end
  local db = 20 * math.log10(vol / 100)
  return string.format("%.0f", db)
end

local last_volume = nil
local last_icon = nil
local last_color = nil
local current_volume = 50
local current_muted = false

local volume_item = sbar.add("item", "widgets.volume", {
  position = "right",
  icon = {
    string = icons.volume._100,
    color = colors.green,
    font = {
      style = settings.font.style_map["Regular"],
      size = 15.0,
    },
  },
  label = {
    string = "--",
    font = { family = settings.font.numbers },
    width = 32,
    padding_left = 2,
    padding_right = 6,
  },
  padding_left = 0,
  padding_right = 0,
})

local function update_volume_widget(v, muted)
  local icon = icon_for_volume(v, muted)
  local color = muted and colors.grey or colors.green
  if last_volume == v and last_icon == icon and last_color == color then return end
  last_volume = v
  last_icon = icon
  last_color = color
  volume_item:set({ icon = { string = icon, color = color }, label = { string = tostring(v) } })
end

volume_item:subscribe("volume_change", function(env)
  if _G.SKETCHYBAR_SUSPENDED then return end
  local v = clamp_int(env.INFO, 0, 100)
  current_volume = v
  update_volume_widget(v, current_muted)
end)

-- Popup setup
local popup_width = 420
local volume_popup = center_popup.create("volume.popup", {
  width = popup_width,
  height = 420,
  popup_height = 26,
  title = "Audio",
  meta = "",
  auto_hide = false,
})
volume_popup.meta_item:set({ drawing = false })
volume_popup.body_item:set({ drawing = false })

local popup_pos = volume_popup.position
local name_width = 140
local value_width = popup_width - name_width

-- Slider at the top
local volume_slider = sbar.add("slider", popup_width, {
  position = popup_pos,
  slider = {
    highlight_color = colors.green,
    percentage = 0,
    background = {
      height = 6,
      corner_radius = 3,
      color = colors.bg2,
    },
    knob = {
      string = "􀀁",
      drawing = true,
    },
  },
  background = { color = colors.bg1, height = 2, y_offset = -20 },
})

local function add_row(key, title, opts)
  opts = opts or {}
  return sbar.add("item", "volume.popup." .. key, {
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
      max_chars = 48,
    },
    background = { drawing = false },
  })
end

local function add_section(key, title)
  return sbar.add("item", "volume.popup.section." .. key, {
    position = popup_pos,
    width = popup_width,
    icon = {
      align = "left",
      string = "── " .. title .. " ──",
      width = popup_width,
      font = { family = settings.font.text, style = settings.font.style_map["Bold"], size = 11.0 },
      color = colors.green,
    },
    label = { drawing = false },
    background = { drawing = false },
  })
end

local row_level = add_row("level", "Level")
local row_mute = add_row("mute", "Mute")

add_section("output", "OUTPUT")
local row_out_device = add_row("out_device", "Device")
local row_out_transport = add_row("out_transport", "Transport")
local row_out_sample = add_row("out_sample", "Sample Rate")
local row_out_channels = add_row("out_channels", "Channels")
local row_out_format = add_row("out_format", "Format")

add_section("input", "INPUT")
local row_in_device = add_row("in_device", "Device")
local row_in_transport = add_row("in_transport", "Transport")
local row_in_sample = add_row("in_sample", "Sample Rate")
local row_in_channels = add_row("in_channels", "Channels")
local row_in_level = add_row("in_level", "Input Level")

volume_popup.add_close_row({ label = "close x" })

-- Helper functions
local function make_bar(percent)
  local filled = math.floor(percent / 10 + 0.5)
  local empty = 10 - filled
  return string.rep("█", filled) .. string.rep("░", empty)
end

local function format_sample_rate(sr)
  local n = tonumber(sr)
  if not n then return "-" end
  if n >= 1000 then
    local khz = n / 1000
    if khz == math.floor(khz) then
      return string.format("%d kHz", khz)
    else
      return string.format("%.1f kHz", khz)
    end
  end
  return string.format("%d Hz", n)
end

local function format_bit_depth(sr)
  local n = tonumber(sr)
  if not n then return "16-bit" end
  if n >= 96000 then return "24-bit (Hi-Res)" end
  if n >= 48000 then return "24-bit" end
  return "16-bit"
end

local function get_transport_icon(transport)
  local t = (transport or ""):lower()
  if t:match("bluetooth") then return "󰂯 Bluetooth" end
  if t:match("usb") then return "󰕓 USB" end
  if t:match("displayport") or t:match("hdmi") then return "󰡁 DisplayPort" end
  if t:match("built%-in") or t:match("builtin") then return "󰌢 Built-in" end
  if t:match("thunderbolt") then return "󱤓 Thunderbolt" end
  return transport or "-"
end

local function parse_audio_devices(output, callback)
  local devices = {}
  local current_device = nil
  local current_props = {}

  for line in output:gmatch("[^\r\n]+") do
    local device_name = line:match("^%s%s%s%s%s%s%s%s(.+):$")
    if device_name then
      if current_device then
        devices[#devices + 1] = { name = current_device, props = current_props }
      end
      current_device = device_name
      current_props = {}
    else
      local key, value = line:match("^%s+(.+):%s*(.+)$")
      if key and value then
        current_props[key:gsub("%s+", "")] = value
      end
    end
  end

  if current_device then
    devices[#devices + 1] = { name = current_device, props = current_props }
  end

  local default_output = nil
  local default_input = nil

  for _, dev in ipairs(devices) do
    if dev.props["DefaultOutputDevice"] == "Yes" then
      default_output = dev
    end
    if dev.props["DefaultInputDevice"] == "Yes" then
      default_input = dev
    end
  end

  callback(default_output, default_input)
end

local function update_level_display(v)
  local db_str = vol_to_db(v)
  row_level:set({ label = { string = string.format("%d%% (%sdB)", v, db_str) } })
  volume_slider:set({ slider = { percentage = v } })
end

local function fetch_audio_info(callback)
  sbar.exec([[osascript -e 'output volume of (get volume settings)']], function(vol_out)
    local vol = tonumber(tostring(vol_out or ""):match("(%d+)")) or 0

    sbar.exec([[osascript -e 'output muted of (get volume settings)']], function(mute_out)
      local muted = tostring(mute_out or ""):match("true") ~= nil

      sbar.exec([[osascript -e 'input volume of (get volume settings)']], function(input_vol_out)
        local input_vol = tonumber(tostring(input_vol_out or ""):match("(%d+)"))

        sbar.exec("system_profiler SPAudioDataType 2>/dev/null", function(profiler_out)
          local profiler_str = tostring(profiler_out or "")

          parse_audio_devices(profiler_str, function(output_dev, input_dev)
            local result = {
              volume = vol,
              muted = muted,
              input_volume = input_vol,
            }

            if output_dev then
              result.out_device = output_dev.name
              result.out_transport = output_dev.props["Transport"] or "-"
              result.out_sample_rate = output_dev.props["CurrentSampleRate"]
              result.out_channels = output_dev.props["OutputChannels"]
            end

            if input_dev then
              result.in_device = input_dev.name
              result.in_transport = input_dev.props["Transport"] or "-"
              result.in_sample_rate = input_dev.props["CurrentSampleRate"]
              result.in_channels = input_dev.props["InputChannels"]
            end

            if callback then callback(result) end
          end)
        end)
      end)
    end)
  end)
end

local function populate_popup()
  fetch_audio_info(function(info)
    current_volume = info.volume
    current_muted = info.muted

    update_level_display(info.volume)
    update_volume_widget(info.volume, info.muted)

    row_mute:set({ label = { string = info.muted and "ON [click to unmute]" or "OFF [click to mute]" } })

    -- Output info
    row_out_device:set({ label = { string = info.out_device or "-" } })
    row_out_transport:set({ label = { string = get_transport_icon(info.out_transport) } })
    row_out_sample:set({ label = { string = format_sample_rate(info.out_sample_rate) } })
    local out_ch = info.out_channels or "2"
    row_out_channels:set({ label = { string = out_ch .. (out_ch == "2" and " (Stereo)" or out_ch == "1" and " (Mono)" or "") } })
    row_out_format:set({ label = { string = format_bit_depth(info.out_sample_rate) } })

    -- Input info
    row_in_device:set({ label = { string = info.in_device or "-" } })
    row_in_transport:set({ label = { string = get_transport_icon(info.in_transport) } })
    row_in_sample:set({ label = { string = format_sample_rate(info.in_sample_rate) } })
    local in_ch = info.in_channels or "1"
    row_in_channels:set({ label = { string = in_ch .. (in_ch == "1" and " (Mono)" or in_ch == "2" and " (Stereo)" or "") } })
    if info.input_volume then
      local in_bar = make_bar(info.input_volume)
      row_in_level:set({ label = { string = string.format("%s %d%%", in_bar, info.input_volume) } })
    else
      row_in_level:set({ label = { string = "-" } })
    end
  end)
end

-- Volume adjustment functions
local function set_volume(new_vol)
  new_vol = clamp_int(new_vol, 0, 100)
  sbar.exec('osascript -e "set volume output volume ' .. tostring(new_vol) .. '"', function()
    current_volume = new_vol
    update_level_display(new_vol)
    update_volume_widget(new_vol, current_muted)
  end)
end

-- Slider 事件订阅 (必须在 set_volume 定义之后)
volume_slider:subscribe("mouse.clicked", function(env)
  local pct = tonumber(env.PERCENTAGE)
  if pct then
    set_volume(pct)
  end
end)

local function toggle_mute()
  sbar.exec('osascript -e "set volume output muted (not output muted of (get volume settings))"', function()
    current_muted = not current_muted
    row_mute:set({ label = { string = current_muted and "ON [click to unmute]" or "OFF [click to mute]" } })
    update_volume_widget(current_volume, current_muted)
  end)
end

row_mute:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" then return end
  toggle_mute()
end)

-- Scroll to adjust volume (throttled)
local scroll_pending = 0
local scroll_armed = false
local function volume_scroll(env)
  if _G.SKETCHYBAR_SUSPENDED then return end
  local info = env and env.INFO or {}
  local delta = tonumber(info.delta) or 0
  if delta == 0 then return end
  if info.modifier ~= "ctrl" then
    delta = delta * 5
  end

  scroll_pending = scroll_pending + delta
  if scroll_armed then return end
  scroll_armed = true

  sbar.delay(0.08, function()
    scroll_armed = false
    local pending = tonumber(scroll_pending) or 0
    scroll_pending = 0
    if pending == 0 then return end
    set_volume(current_volume + pending)
  end)
end

local function volume_on_click(env)
  if env.BUTTON == "right" then
    sbar.exec("/usr/bin/open 'x-apple.systempreferences:com.apple.preference.sound' >/dev/null 2>&1", function() end)
    return
  end
  if env.BUTTON ~= "left" then return end

  if volume_popup.is_showing() then
    volume_popup.hide()
    return
  end

  -- 先设置 slider 为当前音量，避免触发重置
  volume_slider:set({ slider = { percentage = current_volume } })

  volume_popup.show(function()
    populate_popup()
  end)
end

volume_item:subscribe("mouse.clicked", volume_on_click)
volume_item:subscribe("mouse.scrolled", volume_scroll)

-- Initial sync
sbar.exec([[osascript -e 'output volume of (get volume settings)']], function(out, exit_code)
  if exit_code ~= 0 then return end
  local v = tonumber(tostring(out or ""):match("(%d+)"))
  if not v then return end
  current_volume = clamp_int(v, 0, 100)

  sbar.exec([[osascript -e 'output muted of (get volume settings)']], function(mute_out)
    current_muted = tostring(mute_out or ""):match("true") ~= nil
    update_volume_widget(current_volume, current_muted)
  end)
end)
