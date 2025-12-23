local colors = require("colors")
local settings = require("settings")
local app_icons = require("app_icons")
local center_popup = require("center_popup")

local spaces = {}

local active_space = nil
local space_icons = {}

local preview_width = 520
local preview_height = 300
local preview_y_offset = 160
local preview_space_id = nil

local space_preview = center_popup.create("space.preview", {
  width = preview_width,
  height = preview_height,
  y_offset = preview_y_offset,
  title = "SPACE",
  meta = "APPS: NONE",
  image_scale = 0.45,
})

local function show_space_preview(space_id)
  local icons_line = space_icons[space_id] or ""
  local has_icons = icons_line ~= ""
  preview_space_id = space_id
  space_preview.set_title("SPACE " .. tostring(space_id))
  space_preview.set_meta("APPS: " .. (has_icons and icons_line or "NONE"))
  space_preview.set_image("space." .. tostring(space_id))
  space_preview.show()
end

local function maybe_update_preview_apps(space_id, icons_line)
  if preview_space_id ~= space_id then
    return
  end
  if not space_preview.is_showing() then
    return
  end
  local has_icons = icons_line ~= ""
  space_preview.set_meta("APPS: " .. (has_icons and icons_line or "NONE"))
end

-- Mapping from space index to macOS key codes for Command+Number switching
local keycodes_by_space = { [1] = 18, [2] = 19, [3] = 20, [4] = 21, [5] = 23, [6] = 22, [7] = 26, [8] = 28, [9] = 25, [10] = 29 }

for i = 1, 10, 1 do
  local space = sbar.add("space", "space." .. i, {
    position = "right",
    space = i,
    icon = {
      font = { family = settings.font.numbers },
      string = i,
      padding_left = 15,
      padding_right = 8,
      color = colors.white,
      highlight_color = colors.red,
    },
    label = {
      padding_right = 20,
      color = colors.grey,
      highlight_color = colors.white,
      font = "sketchybar-app-font:Regular:16.0",
      y_offset = -1,
    },
    padding_right = 1,
    padding_left = 1,
    background = {
      color = colors.bg1,
      border_width = 1,
      height = 26,
      border_color = colors.black,
    },
    popup = { background = { border_width = 5, border_color = colors.black } }
  })

  spaces[i] = space

  -- Single item bracket for space items to achieve double border on highlight
  local space_bracket = sbar.add("bracket", { space.name }, {
    position = "right",
    background = {
      color = colors.transparent,
      border_color = colors.bg2,
      height = 28,
      border_width = 2
    }
  })

  -- Padding space
  sbar.add("space", "space.padding." .. i, {
    position = "right",
    space = i,
    script = "",
    width = settings.group_paddings,
  })

  space:subscribe("space_change", function(env)
    local selected = env.SELECTED == "true"
    local color = selected and colors.grey or colors.bg2
    space:set({
      icon = { highlight = selected, },
      label = { highlight = selected, string = selected and (space_icons[i] or "") or "" },
      background = { border_color = selected and colors.black or colors.bg2 }
    })
    if selected then
      active_space = i
    end
    space_bracket:set({
      background = { border_color = selected and colors.grey or colors.bg2 }
    })
  end)

  space:subscribe("mouse.clicked", function(env)
    if env.BUTTON == "other" then
      local sid = tonumber(env.SID)
      if sid ~= nil then
        show_space_preview(sid)
      end
    else
      local sid = tonumber(env.SID)
      local keycode = sid and keycodes_by_space[sid] or nil
      if keycode ~= nil then
        sbar.exec("osascript -e 'tell application \"System Events\" to key code " .. keycode .. " using command down'")
      end
    end
  end)
end

local space_window_observer = sbar.add("item", {
  drawing = false,
  updates = true,
})

space_window_observer:subscribe("space_windows_change", function(env)
  local icon_line = ""
  local no_app = true
  for app, count in pairs(env.INFO.apps) do
    no_app = false
    local lookup = app_icons[app]
    local icon = ((lookup == nil) and app_icons["Default"] or lookup)
    icon_line = icon_line .. icon
  end

  if (no_app) then
    icon_line = ""
  end
  sbar.animate("tanh", 10, function()
    local space_index = tonumber(env.INFO.space)
    if space_index ~= nil and spaces[space_index] ~= nil then
      space_icons[space_index] = icon_line
      if space_index == active_space then
        spaces[space_index]:set({ label = { string = icon_line } })
      end
      maybe_update_preview_apps(space_index, icon_line)
    end
  end)
end)

-- Consume one-shot C helper snapshot (space_scan)
space_window_observer:subscribe("space_snapshot", function(env)
  local i = tonumber(env.space)
  local icon_line = ""
  if env.apps and env.apps ~= "" then
    for token in string.gmatch(env.apps, "[^|]+") do
      local app = string.match(token, "([^:]+)") or token
      local lookup = app_icons[app]
      local icon = ((lookup == nil) and app_icons["Default"] or lookup)
      icon_line = icon_line .. icon
    end
  else
    icon_line = ""
  end
  if i ~= nil and spaces[i] ~= nil then
    space_icons[i] = icon_line
    if i == active_space then
      spaces[i]:set({ label = { string = icon_line } })
    end
    maybe_update_preview_apps(i, icon_line)
  end
end)

-- On space change, rescan once to refresh labels for all spaces
space_window_observer:subscribe("space_change", function(_)
  sbar.exec("$CONFIG_DIR/helpers/space_scan/bin/space_scan")
end)

-- Initialize labels on startup
for i = 1, 10 do
  if spaces[i] ~= nil then
    spaces[i]:set({ label = { string = "" } })
  end
end

-- Kick off initial snapshot
sbar.exec("$CONFIG_DIR/helpers/space_scan/bin/space_scan")
