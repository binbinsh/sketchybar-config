local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

-- Minimal dictionary (Raycast Translate) launcher
local dict = sbar.add("item", "widgets.dictionary", {
  position = "right",
  icon = {
    string = icons.translate,
    font = {
      family = settings.font.text,
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

dict:subscribe("mouse.entered", function(_)
  dict:set({ icon = { color = colors.blue } })
end)

dict:subscribe("mouse.exited", function(_)
  dict:set({ icon = { color = colors.white } })
end)

dict:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("open 'raycast://extensions/gebeto/translate/quick-translate'")
    return
  end
  sbar.exec("open 'raycast://extensions/gebeto/translate/instant-translate-view'")
end)


