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
})


local lm_studio_bracket = sbar.add("bracket", "widgets.lm_studio.bracket", {
  lm_studio.name,
}, {
  background = { drawing = false },
  popup = { align = "center" }
})

popup.register(lm_studio_bracket)

local popup_width = 250

-- Pre-create popup children for the LM Studio item
local max_popup_items = 12
local popup_items = {}
local actions = {}

local popup_pos = "popup." .. lm_studio_bracket.name

for i = 1, max_popup_items, 1 do
  local item = sbar.add("item", "widgets.lm_studio.menu." .. i, {
    position = popup_pos,
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

-- One-time click subscriptions for each popup row; action bound dynamically via `actions`
for i = 1, max_popup_items, 1 do
  popup_items[i]:subscribe("mouse.clicked", function(_)
    local fn = actions[i]
    if fn then fn() end
  end)
end

-- Populate status and model list using lms CLI (LLMs only)
local function populate_models()
  -- Hide all rows before repopulating
  for i = 1, max_popup_items, 1 do
    popup_items[i]:set({ drawing = false })
    actions[i] = nil
  end

  local header_idx = 1
  local server_idx = 2
  local port_idx = 3
  local status_idx = 4
  local context_idx = 5
  local ttl_idx = 6
  local loaded_idx = 7
  local toggle_idx = 8
  local models_start_idx = 9

  local function set_header()
    popup_items[header_idx]:set({
      drawing = true,
      icon = {
        drawing = true,
        string = app_icons["LM Studio"] or "",
        font = "sketchybar-app-font:Regular:16.0",
      },
      width = popup_width,
      align = "center",
      label = {
        string = "LM Studio",
        font = { size = 15, style = settings.font.style_map["Bold"] },
        align = "center",
      },
      background = {
        height = 2,
        color = colors.grey,
        y_offset = -15,
      },
    })
  end

  local function set_kv(idx, key, value)
    popup_items[idx]:set({
      drawing = true,
      width = popup_width,
      icon = {
        drawing = true,
        align = "left",
        string = key,
        width = popup_width / 2,
      },
      label = {
        align = "right",
        string = value,
        width = popup_width / 2,
      },
    })
  end

  set_header()

  -- Resolve LMS once in shell and reuse it
  local lms_prefix = [[LMS="$(command -v lms 2>/dev/null || { [ -x "$HOME/.lmstudio/bin/lms" ] && printf "%s" "$HOME/.lmstudio/bin/lms"; })"; ]]

  -- Server status + port, and update topbar label
  sbar.exec([[ /bin/zsh -lc ']] .. lms_prefix .. [[${LMS} status 2>/dev/null' ]], function(status_out)
    local on = (status_out or ""):match("Server:%s*ON") ~= nil
    local port = (status_out or ""):match("port:%s*(%d+)") or "-"
    set_kv(server_idx, "Server:", on and "ON" or "OFF")
    set_kv(port_idx, "Port:", port)

    -- Toggle action row
    local toggle_label = on and "Stop server" or "Start server"
    local toggle_cmd = on and "${LMS} server stop" or "nohup ${LMS} server start >/dev/null 2>&1 &"
    popup_items[toggle_idx]:set({
      drawing = true,
      width = popup_width,
      label = toggle_label,
    })
    actions[toggle_idx] = function()
      popup.hide(lm_studio_bracket)
      sbar.exec("/bin/zsh -lc '" .. lms_prefix .. toggle_cmd .. "'")
    end
  end)

  -- Loaded models memory + details from ps
  sbar.exec([[ /bin/zsh -lc ']] .. lms_prefix .. [[${LMS} ps 2>/dev/null' ]], function(ps_out)
    local function parse_size_to_bytes(sz)
      if not sz or sz == "" then return 0 end
      local num, unit = sz:match("([%d%.]+)%s*([A-Za-z]+)")
      num = tonumber(num or "0") or 0
      unit = (unit or "B"):upper()
      local mul = 1
      if unit == "KB" then mul = 1024
      elseif unit == "MB" then mul = 1024 * 1024
      elseif unit == "GB" then mul = 1024 * 1024 * 1024
      elseif unit == "TB" then mul = 1024 * 1024 * 1024 * 1024
      end
      return math.floor(num * mul)
    end

    local total = 0
    local first_status, first_context, first_ttl = nil, nil, nil
    local loaded_set = {}
    for line in string.gmatch(ps_out or "", "[^\r\n]+") do
      local s = (line or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if s ~= "" and not s:match("^IDENTIFIER") and not s:match("^MODEL") and not s:match("^STATUS") and not s:match("^SIZE") then
        -- Parse columns: IDENTIFIER MODEL STATUS SIZE CONTEXT TTL
        local ident, model, status, size_str, context, ttl = s:match("^(%S+)%s+(%S+)%s+(%S+)%s+([%d%.]+%s+[A-Za-z]+)%s*(%d*)%s*(%S*)")
        if size_str then
          total = total + parse_size_to_bytes(size_str)
        end
        if not first_status then
          first_status = status
          first_context = (context ~= nil and context ~= "" and context) or nil
          first_ttl = (ttl ~= nil and ttl ~= "" and ttl) or nil
        end
        if model and model ~= "" then
          loaded_set[model] = true
        end
      end
    end

    local function format_bytes(n)
      if n >= 1024*1024*1024 then return string.format("%.2f GB", n / (1024*1024*1024))
      elseif n >= 1024*1024 then return string.format("%.2f MB", n / (1024*1024))
      elseif n >= 1024 then return string.format("%.0f KB", n / 1024)
      else return tostring(n) .. " B" end
      end

    set_kv(loaded_idx, "Loaded:", format_bytes(total))
    if first_status and first_status ~= "" then set_kv(status_idx, "Status:", first_status) end
    if first_context and first_context ~= "" then set_kv(context_idx, "Context:", first_context) end
    if first_ttl and first_ttl ~= "" then set_kv(ttl_idx, "TTL:", first_ttl) end
    -- Models list (LLMs only) - executed after ps to use loaded_set
    sbar.exec([[ /bin/zsh -lc ']] .. lms_prefix .. [[${LMS} ls 2>/dev/null' ]], function(out)
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
        local is_embedding = token:lower():find("embed", 1, true) ~= nil
        if is_embedding then return nil end
        local loaded = loaded_set[token] or false
        return { name = token, loaded = loaded }
      end

      for line in string.gmatch(out or "", '[^\r\n]+') do
        local e = parse_line(line)
        if e then table.insert(entries_models, e) end
      end

      local idx = models_start_idx
      local usable_last = max_popup_items - 1 -- keep last for Unload

      for _, e in ipairs(entries_models) do
        if idx > usable_last then break end
        local base = e.name:gsub(".*/", "")
        popup_items[idx]:set({
          drawing = true,
          width = popup_width,
          icon = {
            drawing = true,
            align = "left",
            string = base,
            width = popup_width / 2,
          },
          label = {
            align = "right",
            string = e.loaded and "✓" or "",
            width = popup_width / 2,
          },
        })
        local row_index = idx
        local model_name = e.name
        local base_name = base
        actions[row_index] = function()
          popup.hide(lm_studio_bracket)
          sbar.exec("/bin/zsh -lc '" .. lms_prefix
            .. 'nohup ${LMS} server start >/dev/null 2>&1 &; '
            .. '${LMS} unload --all; '
            .. '${LMS} load "' .. model_name .. '" --identifier "' .. base_name .. '" -y' .. "'")
        end
        idx = idx + 1
      end

      if idx == models_start_idx then
        popup_items[models_start_idx]:set({
          drawing = true,
          width = popup_width,
          label = "Install lms CLI: ~/.lmstudio/bin/lms bootstrap",
        })
        actions[models_start_idx] = function()
          popup.hide(lm_studio_bracket)
          sbar.exec("/bin/zsh -lc '" .. lms_prefix .. "${LMS} bootstrap || true'")
        end
      end

      popup_items[max_popup_items]:set({
        drawing = true,
        width = popup_width,
        label = "Unload all models",
      })
      actions[max_popup_items] = function()
        popup.hide(lm_studio_bracket)
        sbar.exec("/bin/zsh -lc '" .. lms_prefix .. "${LMS} unload --all'")
      end
    end)
  end)
end

lm_studio:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    sbar.exec("open -a 'LM Studio'")
    return
  end

  if env.BUTTON ~= "left" then return end
  popup.toggle(lm_studio_bracket, populate_models)
end)


-- Auto-hide popup on context changes
popup.auto_hide(lm_studio_bracket, lm_studio)

-- Hover color change for the bar icon
lm_studio:subscribe("mouse.entered", function(_)
  lm_studio:set({ icon = { color = colors.blue } })
end)

lm_studio:subscribe("mouse.exited", function(_)
  lm_studio:set({ icon = { color = colors.white } })
end)


