local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

-- Execute the event provider binary which provides the event "network_update"
-- for the primary network interface (auto), fired every 1.0 seconds.
sbar.exec("killall network_load >/dev/null; $CONFIG_DIR/helpers/network_load/bin/network_load auto network_update 1.0")

local popup_width = 480
local rate_label_width = 52

local wifi_up = sbar.add("item", "widgets.wifi1", {
  position = "right",
  padding_left = -5,
  padding_right = 0,
  width = 0,
  icon = {
    padding_right = 0,
    font = {
      family = settings.font.icons,
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    string = icons.wifi.upload,
  },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    align = "right",
    padding_left = 0,
    padding_right = 0,
    width = rate_label_width,
    color = colors.red,
    string = "0 Mbps",
  },
  y_offset = 4,
})

local wifi_down = sbar.add("item", "widgets.wifi2", {
  position = "right",
  padding_left = -5,
  padding_right = 0,
  icon = {
    padding_right = 0,
    font = {
      family = settings.font.icons,
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    string = icons.wifi.download,
  },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 9.0,
    },
    align = "right",
    padding_left = 0,
    padding_right = 0,
    width = rate_label_width,
    color = colors.blue,
    string = "0 Mbps",
  },
  y_offset = -4,
})

local wifi = sbar.add("item", "widgets.wifi.padding", {
  position = "right",
  label = { drawing = false },
})

-- Background around the item
local wifi_bracket = sbar.add("bracket", "widgets.wifi.bracket", {
  wifi.name,
  wifi_up.name,
  wifi_down.name
}, {
  background = {
    color = colors.with_alpha(colors.bg1, 0.2),
    border_color = colors.with_alpha(colors.bg2, 0.2),
    border_width = 2,
  },
})

local wifi_popup = center_popup.create("wifi.popup", {
  width = popup_width,
  height = 360,
  popup_height = 30,
  title = "Wi-Fi",
  meta = "",
})
wifi_popup.meta_item:set({ drawing = false })
wifi_popup.body_item:set({ drawing = false })
local popup_pos = wifi_popup.position

local ssid = sbar.add("item", {
  position = popup_pos,
  icon = {
    font = {
      style = settings.font.style_map["Bold"]
    },
    string = icons.wifi.router,
  },
  width = popup_width,
  align = "center",
  label = {
    font = {
      size = 15,
      style = settings.font.style_map["Bold"]
    },
    string = "????????????",
  },
  background = {
    height = 2,
    color = colors.grey,
    y_offset = -15
  }
})

local hostname = sbar.add("item", {
  position = popup_pos,
  icon = {
    align = "left",
    string = "Hostname:",
    width = popup_width / 2,
  },
  label = {
    max_chars = 20,
    string = "????????????",
    width = popup_width / 2,
    align = "right",
  }
})

local interface_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "Interface:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  }
})

local adapter_mac_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "Adapter MAC:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local ip = sbar.add("item", {
  position = popup_pos,
  icon = {
    align = "left",
    string = "IP:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  }
})

local mask = sbar.add("item", {
  position = popup_pos,
  icon = {
    align = "left",
    string = "Subnet mask:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  }
})

local router = sbar.add("item", {
  position = popup_pos,
  icon = {
    align = "left",
    string = "Router:",
    width = popup_width / 2,
  },
  label = {
    string = "???.???.???.???",
    width = popup_width / 2,
    align = "right",
  },
})

-- Additional Wi‑Fi details (hidden by default; shown when values are available)
local bssid_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "BSSID:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local phy_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "PHY Mode:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local channel_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "Channel:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local security_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "Security:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local interface_mode_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "Interface Mode:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local signal_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "S / N:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local tx_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "Transmit Rate:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local tx_power_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "Transmit Power:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local mcs_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "MCS Index:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local cc_item = sbar.add("item", {
  position = popup_pos,
  drawing = false,
  icon = {
    align = "left",
    string = "Country Code:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

sbar.add("item", { position = "right", width = settings.group_paddings })

local function format_rate(rate)
  local num = tonumber(rate) or 0
  local rounded = math.floor(num + 0.5)
  return string.format("%d Mbps", rounded)
end

wifi_up:subscribe("network_update", function(env)
  local up_num = tonumber(env.upload) or 0
  local down_num = tonumber(env.download) or 0
  local up_color = (up_num == 0) and colors.grey or colors.red
  local down_color = (down_num == 0) and colors.grey or colors.blue
  wifi_up:set({
    icon = { color = up_color },
    label = {
      string = format_rate(env.upload),
      color = up_color
    }
  })
  wifi_down:set({
    icon = { color = down_color },
    label = {
      string = format_rate(env.download),
      color = down_color
    }
  })
end)

wifi:subscribe({"wifi_change", "system_woke"}, function(env)
  sbar.exec("ipconfig getifaddr en0", function(ip)
    local connected = not (ip == "")
    wifi:set({
      icon = {
        string = connected and icons.wifi.connected or icons.wifi.disconnected,
        color = connected and colors.white or colors.red,
      },
    })
  end)
end)

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
  if not info then return end

  if info.ssid and info.ssid ~= "" then ssid:set({ label = info.ssid }) end
  if info.hostname and info.hostname ~= "" then hostname:set({ label = info.hostname }) end
  if info.interface and info.interface ~= "" then
    interface_item:set({ drawing = true, label = info.interface })
  else
    interface_item:set({ drawing = false })
  end
  if info.ip and info.ip ~= "" then ip:set({ label = info.ip }) end
  if info.subnet_mask and info.subnet_mask ~= "" then mask:set({ label = info.subnet_mask }) end
  if info.router and info.router ~= "" then router:set({ label = info.router }) end

  local function set_opt(item, value)
    if not item then return end
    if value and value ~= "" then
      item:set({ drawing = true, label = value })
    else
      item:set({ drawing = false })
    end
  end

  set_opt(bssid_item, info.bssid)
  set_opt(phy_item, info.phy_mode)
  set_opt(channel_item, info.channel)
  set_opt(security_item, info.security)
  set_opt(interface_mode_item, info.interface_mode)
  set_opt(signal_item, info.signal_noise)
  set_opt(tx_item, info.transmit_rate)
  set_opt(tx_power_item, info.transmit_power)
  set_opt(mcs_item, info.mcs_index)
  set_opt(cc_item, info.country_code)
  set_opt(adapter_mac_item, info.adapter_mac)
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
  if env.BUTTON ~= "left" then return end
  if wifi_popup.is_showing() then
    wifi_popup.hide()
  else
    wifi_popup.show(populate_wifi_details)
  end
end

wifi_up:subscribe("mouse.clicked", wifi_on_click)
wifi_down:subscribe("mouse.clicked", wifi_on_click)
wifi:subscribe("mouse.clicked", wifi_on_click)
wifi_popup.add_close_row()
