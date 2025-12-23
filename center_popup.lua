local colors = require("colors")
local settings = require("settings")

local M = { _registry = {} }

function M.register(item)
  if item and item.name then
    M._registry[item.name] = item
  end
  return item
end

function M.hide(item)
  if not item then return end
  item:set({ popup = { drawing = false } })
end

function M.show(item, on_show)
  if not item then return end
  if on_show then on_show() end
  item:set({ popup = { drawing = true } })
end

function M.toggle(item, on_show)
  if not item then return end
  local drawing = item:query().popup.drawing
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
  bracket:subscribe("space_change", function(_)
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
  local show_close = opts.show_close
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
    is_showing = function() return anchor:query().popup.drawing == "on" end,
    set_title = function(text) header_item:set({ icon = { string = title_prefix .. text } }) end,
    set_meta = function(text) meta_item:set({ label = { string = text } }) end,
    set_image = function(path) body_item:set({ background = { image = { string = path } } }) end,
    add_footer_buttons = add_footer_buttons,
    add_close_row = add_close_row,
  }
end

return M
