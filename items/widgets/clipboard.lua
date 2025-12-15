local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

local clipboard = sbar.add("item", "widgets.clipboard", {
  position = "right",
  icon = {
    string = icons.clipboard,
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

clipboard:subscribe("mouse.entered", function(env)
  clipboard:set({ icon = { color = colors.blue } })
end)

clipboard:subscribe("mouse.exited", function(env)
  clipboard:set({ icon = { color = colors.white } })
end)

clipboard:subscribe("mouse.clicked", function(env)
  clipboard:set({ icon = { color = colors.blue } })
  local url = (env.BUTTON == "right")
    and "raycast://extensions/raycast/clipboard-history/ask-clipboard"
    or  "raycast://extensions/raycast/clipboard-history/clipboard-history"
  sbar.exec("open '" .. url .. "'")
  sbar.delay(0.10, function()
    clipboard:set({ icon = { color = colors.white } })
  end)
end)

