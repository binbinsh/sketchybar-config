local colors = require("colors")
local settings = require("settings")
local popup = require("helpers.popup")

local M = {}

function M.create(name, opts)
  opts = opts or {}

  local width = opts.width or 520
  local height = opts.height or 300
  local y_offset = opts.y_offset or 160
  local title = opts.title or "POPUP"
  local meta = opts.meta or ""
  local blur_radius = opts.blur_radius or 40
  local image_scale = opts.image_scale or 0.45
  local corner_radius = opts.corner_radius or 12
  local image_corner_radius = opts.image_corner_radius or 10
  local header_offset = opts.header_offset or -16
  local popup_height = opts.popup_height or 24
  local meta_max_chars = opts.meta_max_chars or 60

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
        color = colors.popup.bg,
        border_color = colors.popup.border,
        border_width = 2,
        corner_radius = corner_radius,
      },
    },
  })

  popup.register(anchor)
  popup.auto_hide(anchor)

  local position = "popup." .. anchor.name

  local title_item = sbar.add("item", name .. ".title", {
    position = position,
    width = width,
    align = "center",
    label = {
      font = {
        family = settings.font.text,
        style = settings.font.style_map["Black"],
        size = 15.0,
      },
      string = title,
    },
    background = {
      height = 2,
      color = colors.grey,
      y_offset = header_offset,
    },
  })

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
      color = colors.grey,
      max_chars = meta_max_chars,
      string = meta,
    },
    background = {
      height = 2,
      color = colors.bg2,
      y_offset = header_offset,
    },
  })

  local body_item = sbar.add("item", name .. ".body", {
    position = position,
    width = width,
    label = { drawing = false },
    icon = { drawing = false },
    background = {
      color = colors.bg1,
      border_color = colors.popup.border,
      border_width = 2,
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
    title_item = title_item,
    meta_item = meta_item,
    body_item = body_item,
    show = function(on_show) popup.show(anchor, on_show) end,
    hide = function() popup.hide(anchor) end,
    is_showing = function() return anchor:query().popup.drawing == "on" end,
    set_title = function(text) title_item:set({ label = { string = text } }) end,
    set_meta = function(text) meta_item:set({ label = { string = text } }) end,
    set_image = function(path) body_item:set({ background = { image = { string = path } } }) end,
  }
end

return M
