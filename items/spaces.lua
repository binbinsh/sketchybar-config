local colors = require("colors")
local settings = require("settings")

local spaces_by_display = {}

-- Stable version:
-- - Primary display keeps names.
-- - Secondary displays show the number only.
local primary_display_id = 1

local spaces_count_helper_path = os.getenv("HOME") .. "/.config/sketchybar/helpers/spaces_count/bin/spaces_count"
local group_gap = (settings.paddings or 3) * 3
local function detect_space_metrics()
  local p = io.popen(string.format("%q 2>/dev/null", spaces_count_helper_path))
  if not p then return 10, 1 end
  local out = p:read("*a") or ""
  p:close()
  local spaces, displays = out:match("(%d+)%s+(%d+)")
  local space_count = tonumber(spaces)
  local display_count = tonumber(displays)
  if not space_count then space_count = 10 end
  if not display_count then display_count = 1 end
  if space_count < 1 then space_count = 1 end
  if space_count > 10 then space_count = 10 end
  if display_count < 1 then display_count = 1 end
  return space_count, display_count
end

local space_count, display_count = detect_space_metrics()

local state_dir = os.getenv("HOME") .. "/.config/sketchybar/states"
local names_state_path = state_dir .. "/spaces_names.lua"

local function ensure_state_dir()
  os.execute('mkdir -p "' .. state_dir .. '"')
end

local default_space_names = {
  [1] = "DEV",
  [2] = "WEB",
  [3] = "CHAT",
  [4] = "MAIL",
  [5] = "DOCS",
  [6] = "MEDIA",
  [7] = "OPS",
  [8] = "NOTE",
  [9] = "MISC",
  [10] = "TMP",
}

local function load_user_space_names()
  local chunk = loadfile(names_state_path, "t", {})
  if not chunk then return {} end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then return {} end

  local out = {}
  for key, value in pairs(data) do
    local idx = tonumber(key)
    if idx and idx >= 1 and idx <= 10 and type(value) == "string" then
      out[idx] = value
    end
  end
  return out
end

local function save_user_space_names(map)
  ensure_state_dir()
  local lines = { "return {" }
  for i = 1, 10 do
    local value = map[i]
    if value ~= nil then
      lines[#lines + 1] = string.format("  [%d] = %q,", i, tostring(value))
    end
  end
  lines[#lines + 1] = "}"
  local file = io.open(names_state_path, "w")
  if not file then return false end
  file:write(table.concat(lines, "\n"))
  file:write("\n")
  file:close()
  return true
end

local user_space_names = load_user_space_names()

local function get_space_name(idx)
  if user_space_names[idx] ~= nil then return user_space_names[idx] end
  return default_space_names[idx] or ""
end

local function applescript_escape(value)
  return tostring(value):gsub("\\", "\\\\"):gsub("\"", "\\\"")
end

local function prompt_space_name(space_index, current_name, on_done)
  local msg = applescript_escape("Rename Space " .. tostring(space_index))
  local def = applescript_escape(current_name or "")
  local title = applescript_escape("Spaces")
  local cmd = "/bin/zsh -lc 'osascript <<EOF\n" ..
    "tell application \"System Events\"\n" ..
    "  activate\n" ..
    "  display dialog \"" .. msg .. "\" default answer \"" .. def .. "\" with title \"" .. title .. "\"\n" ..
    "  text returned of result\n" ..
    "end tell\n" ..
    "EOF'"
  sbar.exec(cmd, function(result, exit_code)
    if tonumber(exit_code) ~= 0 then if on_done then on_done(nil) end return end
    local name = tostring(result or ""):gsub("%s+$", ""):gsub("^%s+", "")
    if on_done then on_done(name) end
  end)
end

local keycodes_by_space = { [1] = 18, [2] = 19, [3] = 20, [4] = 21, [5] = 23, [6] = 22, [7] = 26, [8] = 28, [9] = 25, [10] = 29 }

local function label_for_display(display_id, space_index)
  if display_id == primary_display_id then
    return get_space_name(space_index)
  end
  return ""
end

local function padding_for_display(display_id)
  if display_id == primary_display_id then
    return 10
  end
  return 0
end

local function refresh_space_labels(space_index)
  for display_id = 1, display_count do
    local display_spaces = spaces_by_display[display_id]
    local space = display_spaces and display_spaces[space_index] or nil
    if space then
      space:set({
        label = {
          string = label_for_display(display_id, space_index),
          padding_right = padding_for_display(display_id),
        },
      })
    end
  end
end

for display_id = 1, display_count do
  local display_spaces = {}

  for i = space_count, 1, -1 do
    local space = sbar.add("space", string.format("space.%d.%d", display_id, i), {
      position = "right",
      display = display_id,
      space = i,
      ignore_association = "off",
      icon = {
        font = {
          family = settings.font.numbers,
          style = settings.font.style_map["Semibold"],
          size = 13.0,
        },
        string = i,
        padding_left = 10,
        padding_right = 6,
        color = colors.white,
        highlight_color = colors.green,
      },
      label = {
        padding_right = padding_for_display(display_id),
        color = colors.white,
        highlight_color = colors.green,
        font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 12.0 },
        string = label_for_display(display_id, i),
      },
      padding_right = (i == space_count) and group_gap or 0,
      padding_left = 0,
      background = { drawing = false },
      popup = { drawing = false },
    })

    local was_selected = false
    space:subscribe("space_change", function(env)
      local selected = env.SELECTED == "true"
      if selected == was_selected then return end
      was_selected = selected
      space:set({
        icon = { highlight = selected },
        label = { highlight = selected },
      })
    end)

    space:subscribe("mouse.clicked", function(env)
      local sid = tonumber(env.SID)
      if env.BUTTON == "right" then
        local idx = sid or i
        prompt_space_name(idx, get_space_name(idx), function(new_name)
          if new_name == nil then return end
          user_space_names[idx] = new_name
          save_user_space_names(user_space_names)
          refresh_space_labels(idx)
        end)
        return
      end
      if env.BUTTON ~= "left" then return end
      local keycode = sid and keycodes_by_space[sid] or nil
      if keycode ~= nil then
        sbar.exec("osascript -e 'tell application \"System Events\" to key code " .. keycode .. " using command down'")
      end
    end)

    display_spaces[i] = space
  end

  spaces_by_display[display_id] = display_spaces
end
