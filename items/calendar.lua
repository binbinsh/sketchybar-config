local settings = require("settings")
local colors = require("colors")

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

local cal = sbar.add("item", {
  icon = {
    color = colors.white,
    padding_left = 8,
    font = {
      style = settings.font.style_map["Black"],
      size = 12.0,
    },
  },
  label = {
    color = colors.white,
    padding_right = 8,
    width = 150,
    align = "right",
    font = { family = settings.font.numbers },
  },
  position = "right",
  update_freq = 30,
  padding_left = 1,
  padding_right = 1,
  background = {
    color = colors.bg2,
    border_color = colors.black,
    border_width = 1
  },
})

-- Double border for calendar using a single item bracket
sbar.add("bracket", { cal.name }, {
  background = {
    color = colors.transparent,
    height = 30,
    border_color = colors.grey,
  }
})

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

cal:subscribe({ "forced", "routine", "system_woke" }, function(env)
  local weekday_names = { "日", "一", "二", "三", "四", "五", "六" }
  local weekday_cn = weekday_names[tonumber(os.date("%w")) + 1]
  cal:set({
    icon = "􀧞",
    label = "周" .. weekday_cn .. " " .. os.date("%m月%d日 %H:%M")
  })
end)

cal:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("open -a 'Notion Calendar'")
    return
  end
  if env.BUTTON ~= "left" then return end
  sbar.exec([[osascript -e 'tell application "System Events" to click menu bar item 1 of menu bar 1 of application process "ControlCenter"']])
end)
