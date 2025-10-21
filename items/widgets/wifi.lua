local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local popup = require("helpers.popup")

-- Execute the event provider binary which provides the event "network_update"
-- for the network interface "en0", which is fired every 2.0 seconds.
sbar.exec("killall network_load >/dev/null; $CONFIG_DIR/helpers/event_providers/network_load/bin/network_load en0 network_update 2.0")

local popup_width = 250

local wifi_up = sbar.add("item", "widgets.wifi1", {
  position = "right",
  padding_left = -5,
  width = 0,
  icon = {
    padding_right = 0,
    font = {
      family = settings.font.text,
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
    color = colors.red,
    string = "??? Bps",
  },
  y_offset = 4,
})

local wifi_down = sbar.add("item", "widgets.wifi2", {
  position = "right",
  padding_left = -5,
  icon = {
    padding_right = 0,
    font = {
      family = settings.font.text,
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
    color = colors.blue,
    string = "??? Bps",
  },
  y_offset = -4,
})

local wifi = sbar.add("item", "widgets.wifi.padding", {
  position = "right",
  label = { drawing = false },
  popup = { align = "center", height = 30 },
})

popup.register(wifi)

-- Background around the item
local wifi_bracket = sbar.add("bracket", "widgets.wifi.bracket", {
  wifi.name,
  wifi_up.name,
  wifi_down.name
}, {
  background = { color = colors.bg1 }
})

local ssid = sbar.add("item", {
  position = "popup." .. wifi.name,
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
    max_chars = 18,
    string = "????????????",
  },
  background = {
    height = 2,
    color = colors.grey,
    y_offset = -15
  }
})

local hostname = sbar.add("item", {
  position = "popup." .. wifi.name,
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

local ip = sbar.add("item", {
  position = "popup." .. wifi.name,
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
  position = "popup." .. wifi.name,
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
  position = "popup." .. wifi.name,
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
  position = "popup." .. wifi.name,
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
  position = "popup." .. wifi.name,
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
  position = "popup." .. wifi.name,
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
  position = "popup." .. wifi.name,
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

local signal_item = sbar.add("item", {
  position = "popup." .. wifi.name,
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
  position = "popup." .. wifi.name,
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

local mcs_item = sbar.add("item", {
  position = "popup." .. wifi.name,
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
  position = "popup." .. wifi.name,
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

local adapter_mac_item = sbar.add("item", {
  position = "popup." .. wifi.name,
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

sbar.add("item", { position = "right", width = settings.group_paddings })

wifi_up:subscribe("network_update", function(env)
  local up_color = (env.upload == "000 Bps") and colors.grey or colors.red
  local down_color = (env.download == "000 Bps") and colors.grey or colors.blue
  wifi_up:set({
    icon = { color = up_color },
    label = {
      string = env.upload,
      color = up_color
    }
  })
  wifi_down:set({
    icon = { color = down_color },
    label = {
      string = env.download,
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

local function populate_wifi_details()
  sbar.exec("networksetup -getcomputername", function(result)
    hostname:set({ label = result })
  end)
  sbar.exec("ipconfig getifaddr en0", function(result)
    ip:set({ label = result })
  end)
  -- Single system_profiler call to fetch current Wi‑Fi details
  sbar.exec("system_profiler SPAirPortDataType", function(sp)
    local function parse_sp_airport(output)
      local r = {}
      local in_en0 = false
      local in_current = false
      for line in string.gmatch(output or "", "[^\r\n]+") do
        if not in_en0 then
          if line:match("^%s*en0:%s*$") then
            in_en0 = true
          end
        else
          if not in_current then
            local mac = line:match("^%s*MAC Address:%s*(.+)$")
            if mac then r.adapter_mac = mac end
            if line:match("^%s*Current Network Information:%s*$") then
              in_current = true
            end
            if line:match("^%s*%w[%w%d]+:%s*$") and not line:match("^%s*en0:%s*$") then
              break
            end
          else
            if line:match("^%s*Other Local Wi%-Fi Networks:%s*$") then
              break
            end
            if not r.ssid then
              local ss = line:match("^%s*(.-):%s*$")
              if ss and ss ~= "" then r.ssid = ss end
            else
              local key, value = line:match("^%s*([%w%s%/%-]+):%s*(.+)$")
              if key and value then
                key = key:gsub("%s+$", "")
                if key == "PHY Mode" then r.phy_mode = value
                elseif key == "Channel" then r.channel = value
                elseif key == "Country Code" then r.country_code = value
                elseif key == "Security" then r.security = value
                elseif key == "Signal / Noise" then r.signal_noise = value
                elseif key == "Transmit Rate" then r.tx_rate = value
                elseif key == "MCS Index" then r.mcs_index = value
                elseif key == "BSSID" then r.bssid = value
                end
              end
            end
          end
        end
      end
      return r
    end

    local vals = parse_sp_airport(sp)
    if vals.ssid and vals.ssid ~= "" then ssid:set({ label = vals.ssid }) end

    local function set_opt(item, value)
      if not item then return end
      if value and value ~= "" then
        item:set({ drawing = true, label = value })
      else
        item:set({ drawing = false })
      end
    end

    set_opt(bssid_item, vals.bssid)
    set_opt(phy_item, vals.phy_mode)
    set_opt(channel_item, vals.channel)
    set_opt(security_item, vals.security)
    set_opt(signal_item, vals.signal_noise)
    set_opt(tx_item, vals.tx_rate)
    set_opt(mcs_item, vals.mcs_index)
    set_opt(cc_item, vals.country_code)
    set_opt(adapter_mac_item, vals.adapter_mac)
  end)
  sbar.exec("networksetup -getinfo Wi-Fi | awk -F 'Subnet mask: ' '/^Subnet mask: / {print $2}'", function(result)
    mask:set({ label = result })
  end)
  sbar.exec("networksetup -getinfo Wi-Fi | awk -F 'Router: ' '/^Router: / {print $2}'", function(result)
    router:set({ label = result })
  end)
end

local function wifi_on_click(env)
  if env.BUTTON == "right" then
    sbar.exec("open 'x-apple.systempreferences:com.apple.wifi-settings-extension' || open 'x-apple.systempreferences:com.apple.Network-Settings.extension'")
    return
  end
  popup.toggle(wifi, populate_wifi_details)
end

wifi_up:subscribe("mouse.clicked", wifi_on_click)
wifi_down:subscribe("mouse.clicked", wifi_on_click)
wifi:subscribe("mouse.clicked", wifi_on_click)
popup.auto_hide(wifi)

local function copy_label_to_clipboard(env)
  local label = sbar.query(env.NAME).label.value
  sbar.exec("echo \"" .. label .. "\" | pbcopy")
  sbar.set(env.NAME, { label = { string = icons.clipboard, align="center" } })
  sbar.delay(1, function()
    sbar.set(env.NAME, { label = { string = label, align = "right" } })
  end)
end

ssid:subscribe("mouse.clicked", copy_label_to_clipboard)
hostname:subscribe("mouse.clicked", copy_label_to_clipboard)
ip:subscribe("mouse.clicked", copy_label_to_clipboard)
mask:subscribe("mouse.clicked", copy_label_to_clipboard)
router:subscribe("mouse.clicked", copy_label_to_clipboard)
bssid_item:subscribe("mouse.clicked", copy_label_to_clipboard)
phy_item:subscribe("mouse.clicked", copy_label_to_clipboard)
channel_item:subscribe("mouse.clicked", copy_label_to_clipboard)
security_item:subscribe("mouse.clicked", copy_label_to_clipboard)
signal_item:subscribe("mouse.clicked", copy_label_to_clipboard)
tx_item:subscribe("mouse.clicked", copy_label_to_clipboard)
mcs_item:subscribe("mouse.clicked", copy_label_to_clipboard)
cc_item:subscribe("mouse.clicked", copy_label_to_clipboard)
adapter_mac_item:subscribe("mouse.clicked", copy_label_to_clipboard)
