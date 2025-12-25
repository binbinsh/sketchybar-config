local colors = require("colors")
local settings = require("settings")

local M = {
  _registry = {},
  _open = {},
  _space_change_mode = {},
  _pin = {},
  _show_token = {},
}

-- Forward declaration (used by the watcher defined below).
local popup_drawing

local popup_context_helper_path = os.getenv("HOME") .. "/.config/sketchybar/helpers/popup_context/bin/popup_context"

-- Popup behavior notes:
-- - Default: popups FOLLOW the active Space/Display (opts.pin=false).
--   This matches SketchyBar's natural behavior and ensures the popup is always
--   visible where you are working.
-- - To avoid the "empty popup" frame during Space/Display transitions while a
--   popup is open, the default transition mode is "refresh" for non-pinned popups.
-- - Optional pinning: set opts.pin=true to keep a popup on the Space+Display
--   where it was opened.
-- - You can override transition handling via opts.space_change:
--   - "refresh": force a redraw after transitions
--   - "hide"   : close the popup on space/display change
--   - "none"   : do nothing
local SPACE_CHANGE_DELAY = 0.40
local watcher = nil
local space_token = 0
local timer_armed = false
local pending_refresh = {}

local function normalize_space_mode(value)
  if value == nil then return nil end
  if value == false then return "none" end
  local s = tostring(value):lower()
  if s == "hide" then return "hide" end
  if s == "refresh" or s == "reopen" then return "refresh" end
  if s == "none" or s == "off" or s == "ignore" then return "none" end
  return nil
end

local function file_exists(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

local function popup_item_names(anchor)
  if not anchor then return {} end
  local ok, result = pcall(function() return anchor:query() end)
  if not ok or type(result) ~= "table" then return {} end
  local popup = result.popup
  if type(popup) == "table" and type(popup.items) == "table" then
    local names = {}
    for _, v in ipairs(popup.items) do
      if type(v) == "string" and v ~= "" then
        names[#names + 1] = v
      end
    end
    return names
  end
  return {}
end

local function set_association_for_popup(anchor, space, display)
  if not anchor or not anchor.name then return end
  local props = {}
  if space ~= nil then props.associated_space = space end
  if display ~= nil then props.associated_display = display end
  if next(props) == nil then return end

  local names = popup_item_names(anchor)
  names[#names + 1] = anchor.name
  for _, name in ipairs(names) do
    sbar.set(name, props)
  end
end

local function clear_association_for_popup(anchor)
  if not anchor or not anchor.name then return end
  local names = popup_item_names(anchor)
  names[#names + 1] = anchor.name
  for _, name in ipairs(names) do
    sbar.set(name, { associated_space = "", associated_display = "" })
  end
end

local function resolve_popup_context(callback)
  if not callback then return end
  if not file_exists(popup_context_helper_path) then
    callback(nil)
    return
  end
  sbar.exec(popup_context_helper_path, function(out, exit_code)
    if tonumber(exit_code) ~= 0 or type(out) ~= "table" then
      callback(nil)
      return
    end
    local space = tonumber(out.space)
    local display = tonumber(out.display)
    if not space or space < 1 then space = nil end
    if display == nil or display < 0 then display = nil end
    callback({ space = space, display = display })
  end)
end

local function ensure_watcher()
  if watcher then return end
  watcher = sbar.add("item", "center_popup.watcher", {
    drawing = false,
    updates = true,
    label = { drawing = false },
    icon = { drawing = false },
    background = { drawing = false },
  })

  local function handle_transition()
    space_token = space_token + 1
    local token_at = space_token

    -- Track open popups at the time of the transition. For "refresh" we keep
    -- the popup open (so it follows the active Space/Display) and perform a
    -- quick toggle after the transition to force a redraw of popup children.
    for name, item in pairs(M._registry) do
      if item then
        local is_open = (M._open[name] == true)
        if not is_open then
          -- Fallback to querying the real state (covers persisted popup state
          -- across reloads or popups opened outside this module).
          is_open = (popup_drawing(item) == "on")
          if is_open then M._open[name] = true end
        end

        if is_open then
          local mode = M._space_change_mode[name] or "refresh"
          if mode == "hide" then
            M.hide(item)
          elseif mode == "refresh" then
            pending_refresh[name] = true
          end
        end
      end
    end

    if timer_armed then return end
    timer_armed = true

    sbar.delay(SPACE_CHANGE_DELAY, function()
      timer_armed = false
      if token_at ~= space_token then
        -- Another transition happened; wait for the last one.
        handle_transition()
        return
      end

      for name, _ in pairs(pending_refresh) do
        local item = M._registry[name]
        if item and (M._space_change_mode[name] or "refresh") == "refresh" and M._open[name] == true then
          -- Force redraw of popup children with a very short toggle.
          item:set({ popup = { drawing = false } })
          sbar.delay(0.02, function()
            -- Only re-open if still intended open and no newer transition happened.
            if token_at ~= space_token then return end
            if M._open[name] ~= true then return end
            item:set({ popup = { drawing = true } })
          end)
        end
      end
      pending_refresh = {}
    end)
  end

  watcher:subscribe({ "space_change", "display_change" }, function(_)
    handle_transition()
  end)
end

popup_drawing = function(item)
  if not item then return "off" end
  local ok, result = pcall(function() return item:query() end)
  if not ok or type(result) ~= "table" then return "off" end

  local popup = result.popup
  if type(popup) == "table" and type(popup.drawing) == "string" then
    return popup.drawing
  end
  if type(popup) == "string" then
    return popup
  end
  if type(result["popup.drawing"]) == "string" then
    return result["popup.drawing"]
  end
  return "off"
end

function M.register(item)
  if item and item.name then
    M._registry[item.name] = item
  end
  return item
end

function M.hide(item)
  if not item then return end
  local name = item.name
  if name then
    M._open[name] = false
    M._show_token[name] = (M._show_token[name] or 0) + 1 -- cancel pending async show
  end
  local pin = name and M._pin[name] == true
  item:set({ popup = { drawing = false } })
  if pin then
    clear_association_for_popup(item)
  end
end

function M.show(item, on_show)
  if not item then return end
  local name = item.name
  local token = 0
  if name then
    token = (M._show_token[name] or 0) + 1
    M._show_token[name] = token
  end

  local function do_open()
    if name and M._show_token[name] ~= token then return end
    if on_show then on_show() end
    if name then M._open[name] = true end
    item:set({ popup = { drawing = true } })
  end

  local pin = name and M._pin[name] == true
  if not pin then
    do_open()
    return
  end

  resolve_popup_context(function(ctx)
    if name and M._show_token[name] ~= token then return end
    -- Always clear stale pinning first; otherwise a failed context lookup can
    -- leave the popup pinned to an old space/display and effectively invisible.
    clear_association_for_popup(item)

    -- Only pin when we have BOTH a space and a display; otherwise fall back to
    -- the default (visible everywhere) behavior so the user never gets "no popup".
    if ctx and ctx.space ~= nil and ctx.display ~= nil then
      set_association_for_popup(item, ctx.space, ctx.display)
    end
    do_open()
  end)
end

function M.toggle(item, on_show)
  if not item then return end
  local drawing = popup_drawing(item)
  if drawing == "off" then
    M.show(item, on_show)
  else
    M.hide(item)
  end
end

function M.auto_hide(bracket, widget)
  if not widget then
    widget = bracket
  end

  if not bracket then return end

  widget:subscribe("mouse.exited.global", function(_)
    M.hide(bracket)
  end)

  bracket:subscribe("front_app_switched", function(_)
    M.hide(bracket)
  end)
end

function M.create(name, opts)
  opts = opts or {}

  local width = opts.width or opts.fixed_width or 480
  local height = opts.height or 300
  local y_offset = opts.y_offset or 160
  local title = opts.title or "POPUP"
  local meta = opts.meta or ""
  local blur_radius = opts.blur_radius or 40
  local image_scale = opts.image_scale or 0.45
  local corner_radius = opts.corner_radius or 12
  local image_corner_radius = opts.image_corner_radius or 10
  local header_offset = opts.header_offset or 0
  local popup_height = opts.popup_height or 24
  local meta_max_chars = opts.meta_max_chars or 60
  local auto_hide = opts.auto_hide
  if auto_hide == nil then auto_hide = false end
  local pin = opts.pin
  if pin == nil then pin = false end
  local space_mode = normalize_space_mode(opts.space_change)
  if not space_mode then
    -- Default:
    -- - pinned popups don't need transition handling (they don't move)
    -- - non-pinned popups should refresh after transitions to avoid empty frames
    space_mode = pin and "none" or "refresh"
  end
  local show_close = opts.show_close
  -- Default: show close button row (opt-out per popup via show_close=false).
  if show_close == nil then show_close = true end
  local glass_alpha = opts.glass_alpha or 0.6
  local glow_alpha = opts.glow_alpha or 0.5
  local accent = opts.accent_color or colors.green
  local title_prefix = opts.title_prefix or ""
  local glass_bg = colors.with_alpha(colors.popup.bg, glass_alpha)
  local glass_panel = colors.with_alpha(colors.bg1, glass_alpha * 0.9)
  local glow = colors.with_alpha(accent, glow_alpha)
  local glow_dim = colors.with_alpha(accent, glow_alpha * 0.5)
  local meta_tint = colors.with_alpha(accent, 0.8)

  local anchor = sbar.add("item", name, {
    position = "center",
    width = 1,
    icon = { drawing = false },
    label = { drawing = false },
    background = { drawing = false },
    popup = {
      align = "center",
      y_offset = y_offset,
      height = popup_height,
      blur_radius = blur_radius,
      background = {
        color = glass_bg,
        border_color = glow,
        border_width = 1,
        corner_radius = corner_radius,
      },
    },
  })

  M.register(anchor)
  M._space_change_mode[anchor.name] = space_mode
  M._pin[anchor.name] = pin
  if space_mode ~= "none" then
    ensure_watcher()
  end
  if auto_hide then
    M.auto_hide(anchor)
  end

  local position = "popup." .. anchor.name

  local header_item = sbar.add("item", name .. ".header", {
    position = position,
    width = width,
    align = "center",
    y_offset = header_offset,
    icon = {
      align = "center",
      string = title_prefix .. title,
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 14.0,
      },
      color = glow,
    },
    label = { drawing = false },
    background = {
      height = 1,
      color = glow,
    },
  })

  local footer_rows = {}
  local function add_footer_buttons(buttons)
    if not buttons or #buttons == 0 then return footer_rows end
    for i, btn in ipairs(buttons) do
      local item = sbar.add("item", name .. ".footer." .. tostring(#footer_rows + 1), {
        position = position,
        width = width,
        align = "right",
        icon = { drawing = false },
        label = {
          string = btn.label or "close x",
          font = {
            family = settings.font.text,
            style = settings.font.style_map["Semibold"],
            size = 11.0,
          },
          color = colors.white,
          padding_right = 8,
          padding_left = 8,
          align = "right",
        },
        background = { drawing = false },
      })
      if btn.on_click then
        item:subscribe("mouse.clicked", function(_)
          btn.on_click()
        end)
      end
      footer_rows[#footer_rows + 1] = item
    end
    return footer_rows
  end

  local function add_close_row(opts)
    if not show_close then return footer_rows end
    opts = opts or {}
    return add_footer_buttons({
      {
        label = opts.label or "close x",
        on_click = function() M.hide(anchor) end,
      },
    })
  end

  local meta_item = sbar.add("item", name .. ".meta", {
    position = position,
    width = width,
    align = "center",
    label = {
      font = {
        family = settings.font.text,
        style = settings.font.style_map["Semibold"],
        size = 11.0,
      },
      color = meta_tint,
      max_chars = meta_max_chars,
      string = meta,
    },
    background = {
      height = 1,
      color = glow_dim,
      y_offset = header_offset,
    },
  })

  local body_item = sbar.add("item", name .. ".body", {
    position = position,
    width = width,
    label = { drawing = false },
    icon = { drawing = false },
    background = {
      color = glass_panel,
      border_color = glow,
      border_width = 1,
      corner_radius = corner_radius,
      height = height,
      image = {
        corner_radius = image_corner_radius,
        scale = image_scale,
      },
    },
  })

  return {
    anchor = anchor,
    position = position,
    width = width,
    height = height,
    title_item = header_item,
    close_item = footer_rows[#footer_rows],
    meta_item = meta_item,
    body_item = body_item,
    show = function(on_show) M.show(anchor, on_show) end,
    hide = function() M.hide(anchor) end,
    is_showing = function() return popup_drawing(anchor) == "on" end,
    set_title = function(text) header_item:set({ icon = { string = title_prefix .. text } }) end,
    set_meta = function(text) meta_item:set({ label = { string = text } }) end,
    set_image = function(path) body_item:set({ background = { image = { string = path } } }) end,
    add_footer_buttons = add_footer_buttons,
    add_close_row = add_close_row,
  }
end

return M
