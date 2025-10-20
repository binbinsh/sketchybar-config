local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")
local popup = require("helpers.popup")

local lm_studio = sbar.add("item", "widgets.lm_studio", {
  position = "right",
  icon = {
    string = app_icons["LM Studio"] or "",
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

popup.register(lm_studio)

-- Pre-create popup children for the LM Studio item
local max_popup_items = 12
local popup_items = {}

for i = 1, max_popup_items, 1 do
  local item = sbar.add("item", "widgets.lm_studio.menu." .. i, {
    position = "popup.widgets.lm_studio",
    drawing = false,
    padding_left = settings.paddings,
    padding_right = settings.paddings,
    icon = { drawing = false },
    label = {
      font = {
        family = settings.font.text,
        style = settings.font.style_map["Semibold"],
        size = 15.0,
      },
      padding_left = 6,
      padding_right = 6,
    },
  })
  popup_items[i] = item
end

-- Populate model list using lms CLI
local function populate_models()
  -- Hide all rows before repopulating
  for i = 1, max_popup_items, 1 do
    popup_items[i]:set({ drawing = false })
  end

  -- Resolve LMS once in shell and reuse it
  local lms_prefix = [[LMS="$(command -v lms 2>/dev/null || { [ -x "$HOME/.lmstudio/bin/lms" ] && printf "%s" "$HOME/.lmstudio/bin/lms"; })"; ]]
  local list_cmd = [[/bin/zsh -lc ']] .. lms_prefix .. [[${LMS} ls 2>/dev/null']]

  sbar.exec(list_cmd, function(out)
    local entries_embeddings = {}
    local entries_models = {}

    local function parse_line(line)
      local s = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if s == "" then return nil end
      -- drop headers/notes
      if s:match("^EMBEDDING") or s:match("^LLM") or s:match("^PARAMS") or s:match("^ARCH") or s:match("^SIZE") then return nil end
      if s:match("^You have ") then return nil end
      -- first column token
      local token = s:match("^(%S+)")
      if not token or token == "" then return nil end
      local loaded = (s:find("LOADED", 1, true) ~= nil) or (s:find("✓", 1, true) ~= nil)
      local is_embedding = token:lower():find("embed", 1, true) ~= nil
      return { name = token, loaded = loaded, is_embedding = is_embedding }
    end

    for line in string.gmatch(out or "", '[^\r\n]+') do
      local e = parse_line(line)
      if e then
        if e.is_embedding then table.insert(entries_embeddings, e) else table.insert(entries_models, e) end
      end
    end

    local idx = 1
    local usable_slots = max_popup_items - 1 -- reserve last for Unload

    local function render_group(group)
      for _, e in ipairs(group) do
        if idx > usable_slots then return end
        -- Display base name while loading by base, but keep original token for CLI
        local base = e.name:gsub(".*/", "")
        local label = base .. (e.loaded and " ✓" or "")
        popup_items[idx]:set({
          drawing = true,
          label = label,
          click_script = "/bin/zsh -lc '" .. lms_prefix
            .. "sketchybar --set widgets.lm_studio popup.drawing=off; "
            .. '${LMS} unload --all; '
            .. '${LMS} load "' .. e.name .. '" --identifier "' .. base .. '" -y '
            .. '|| ${LMS} server start --model "' .. e.name .. '" --background'
            .. "'",
        })
        idx = idx + 1
      end
    end

    -- embeddings first, then models
    render_group(entries_embeddings)
    render_group(entries_models)

    if idx == 1 then
      popup_items[1]:set({
        drawing = true,
        label = "Install lms CLI: ~/.lmstudio/bin/lms bootstrap",
        click_script = "/bin/zsh -lc '" .. lms_prefix .. "sketchybar --set widgets.lm_studio popup.drawing=off; ${LMS} bootstrap || true'",
      })
    end

    popup_items[max_popup_items]:set({
      drawing = true,
      label = "Unload all models",
      click_script = [[/bin/zsh -lc ']] .. lms_prefix .. [[sketchybar --set widgets.lm_studio popup.drawing=off; ${LMS} unload --all']],
    })
  end)
end

lm_studio:subscribe("mouse.entered", function(env)
  lm_studio:set({ icon = { color = colors.blue } })
end)

lm_studio:subscribe("mouse.exited", function(env)
  lm_studio:set({ icon = { color = colors.white } })
end)

lm_studio:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("open -a 'LM Studio'")
    return
  end

  if env.BUTTON ~= "left" then return end

  lm_studio:set({ icon = { color = colors.blue } })
  popup.toggle(lm_studio, populate_models)
  sbar.delay(0.10, function()
    lm_studio:set({ icon = { color = colors.white } })
  end)
end)


-- Auto-hide popup on context changes
popup.auto_hide(lm_studio)


