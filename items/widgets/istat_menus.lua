local colors = require("colors")
local settings = require("settings")

-- Find the iStat Menus Combined menu extra and add it as an alias
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Concurrency and idempotency guards within one reload cycle
local alias_in_progress = false
local alias_created = false
local bracket_added = false
local padding_added = false

local function extract_istat_target(result)
  -- Handle parsed JSON (Lua table) or raw string
  local t = type(result)
  if t == "table" then
    -- Prefer entries that include 'Menu' (some systems expose a "Menu Bar"-scoped string)
    local preferred = nil
    local fallback = nil
    for _, entry in ipairs(result) do
      if type(entry) == "string" and entry:find("com%.bjango%.istatmenus%.combined") then
        if entry:find("Menu") then preferred = trim(entry) else fallback = trim(entry) end
      end
    end
    return preferred or fallback
  elseif t == "string" then
    if result == "" then return nil end
    local quoted = result:match('"([^\"]*com%.bjango%.istatmenus%.combined[^\"]*)"')
    if quoted and quoted ~= "" then return trim(quoted) end
    local line = result:match("[^\n]*com%.bjango%.istatmenus%.combined[^\n]*")
    if line and line ~= "" then
      return trim(line:gsub('^%s*"?', ""):gsub('"?%s*$', ""))
    end
    return nil
  else
    return nil
  end
end

local function add_istat_alias(alias_target)
  -- Helper: ensure bracket/padding exist only once (avoid noisy queries)
  local function ensure_bracket_padding()
    if not bracket_added then
      sbar.add("bracket", "widgets.istat_menus.bracket", { "istat_menus" }, {
        background = { color = colors.bg1 }
      })
      bracket_added = true
    end
    if not padding_added then
      sbar.add("item", "widgets.istat_menus.padding", {
        position = "right",
        width = settings.group_paddings
      })
      padding_added = true
    end
  end

  -- Add fresh alias and rename in one command; guarded to avoid races
  local add_cmd = string.format(
    [[/bin/zsh -lc 'sketchybar --add alias "%s" right ]] ..
    [[--rename "%s" istat_menus ]] ..
    [[--set istat_menus background.drawing=off ]] ..
    [[icon.padding_left=3 icon.padding_right=3 ]] ..
    [[label.padding_left=3 label.padding_right=3 ]] ..
    [[click_script="open -a '\''Activity Monitor'\''"']],
    alias_target,
    alias_target
  )
  sbar.exec(add_cmd, function()
    alias_created = true
    ensure_bracket_padding()
  end)
end

-- Retry probe: keep checking for the iStat alias target shortly after reload
local retries_remaining = 60
local istat_probe = sbar.add("item", "widgets.istat_menus.probe", {
  drawing = false,
  updates = true,
  update_freq = 1
})

local function try_alias_once()
  if alias_created or alias_in_progress then return end
  alias_in_progress = true
  sbar.exec("/bin/zsh -lc 'sketchybar --query default_menu_items'", function(out)
    local alias_target = extract_istat_target(out)
    if alias_target and alias_target ~= "" then
      add_istat_alias(alias_target)
      istat_probe:set({ updates = false })
    else
      retries_remaining = retries_remaining - 1
      if retries_remaining <= 0 then
        istat_probe:set({ updates = false })
      end
      alias_in_progress = false
    end
  end)
end

istat_probe:subscribe("routine", function()
  try_alias_once()
end)


