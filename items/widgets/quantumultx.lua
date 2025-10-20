local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")
local popup = require("helpers.popup")

local qx = sbar.add("item", "widgets.quantumultx", {
  position = "right",
  icon = {
    string = app_icons["Quantumult X"] or "",
    font = "sketchybar-app-font:Regular:16.0",
    color = colors.white,
  },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = settings.paddings,
  padding_right = settings.paddings,
  updates = true,
  popup = { align = "center" },
})

popup.register(qx)

local popup_width = 250


local qx_ip = sbar.add("item", {
  position = "popup." .. qx.name,
  icon = {
    align = "left",
    string = "Public IP:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local qx_location = sbar.add("item", {
  position = "popup." .. qx.name,
  icon = {
    align = "left",
    string = "Location:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

local qx_isp = sbar.add("item", {
  position = "popup." .. qx.name,
  icon = {
    align = "left",
    string = "ISP:",
    width = popup_width / 2,
  },
  label = {
    string = "…",
    width = popup_width / 2,
    align = "right",
  },
})

qx:subscribe("mouse.entered", function(env)
  qx:set({ icon = { color = colors.blue } })
end)

qx:subscribe("mouse.exited", function(env)
  qx:set({ icon = { color = colors.white } })
end)

local function trim_newline(s)
  return (s or ""):gsub("\r", ""):gsub("\n$", "")
end

local function update_ipinfo()
  -- ipinfo.io plain-text endpoints to avoid JSON parsing dependencies
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


local function toggle_popup_and_refresh(env)
  if env.BUTTON == "right" then
    sbar.exec("open -a 'Quantumult X'")
    return
  end

  popup.toggle(qx, function()
    qx_ip:set({ label = "…" })
    qx_location:set({ label = "…" })
    qx_isp:set({ label = "…" })
    update_ipinfo()
  end)
end

qx:subscribe("mouse.clicked", toggle_popup_and_refresh)
popup.auto_hide(qx)


