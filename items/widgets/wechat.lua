local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

-- Simple WeChat widget that shows unread count from the Dock badge.

local wechat = sbar.add("item", "widgets.wechat", {
  position = "right",
  icon = {
    string = app_icons["WeChat"] or app_icons["微信"],
    font = "sketchybar-app-font:Regular:19.0",
    color = colors.white,
  },
  label = {
    drawing = true,
    string = "",
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
    },
    color = colors.white,
  },
  background = { drawing = false },
  padding_left = settings.paddings,
  padding_right = settings.paddings,
  updates = true,
})

local function jxa_dock_badge_for(app_name)
  local js_lines = {
    "function run(argv) {",
    "  var app = Application.currentApplication();",
    "  app.includeStandardAdditions = true;",
    "  // Read Dock tile AXStatusLabel for WeChat/微信",
    "  try {",
    "    var se = Application('System Events');",
    "    var dock = se.processes.byName('Dock');",
    "    var list = dock.lists[0];",
    "    var tiles = list.uiElements();",
    "    for (var i = 0; i < tiles.length; i++) {",
    "      var t = tiles[i];",
    "      var nm = '';",
    "      try { nm = String(t.name()); } catch (e) {}",
    "      if (nm.indexOf('WeChat') !== -1 || nm.indexOf('微信') !== -1) {",
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
    "}"
  }
  local parts = {}
  for _, line in ipairs(js_lines) do
    parts[#parts+1] = "-e " .. string.format("%q", line)
  end
  return "/usr/bin/osascript -l JavaScript " .. table.concat(parts, " ") .. " -- " .. string.format("%q", app_name)
end


local function trim(s)
  if not s then return "" end
  return (s:gsub("\n$", "")):gsub("^%s+", ""):gsub("%s+$", "")
end

local function update_badge()
  local cmd = jxa_dock_badge_for("WeChat")
  sbar.exec(cmd, function(out)
    local badge = trim(out or "")
    if badge == "" then
      wechat:set({ label = { drawing = false, string = "" }, icon = { color = colors.white } })
    else
      wechat:set({ label = { drawing = true, string = badge }, icon = { color = colors.green } })
    end
  end)
end

wechat:subscribe("mouse.entered", function(_)
  wechat:set({ icon = { color = colors.blue } })
end)

wechat:subscribe("mouse.exited", function(_)
  update_badge()
end)

wechat:subscribe("mouse.clicked", function(_)
  wechat:set({ icon = { color = colors.blue } })
  sbar.exec("/bin/zsh -lc 'open -a WeChat || open -b com.tencent.xinWeChat || open -a 微信'", function(_)
    sbar.delay(0.10, function()
      update_badge()
    end)
  end)
end)

-- Update cycle: every 10s is enough
wechat:set({ update_freq = 10 })
wechat:subscribe("routine", function(_) update_badge() end)

-- Also refresh on app events to be reactive
wechat:subscribe({"front_app_switched", "system_woke"}, function(_) update_badge() end)

-- Initial paint
update_badge()


