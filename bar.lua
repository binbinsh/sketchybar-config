local colors = require("colors")

-- Equivalent to the --bar domain
sbar.bar({
  height = 32,
  topmost = true,
  -- Visual effects (blur + translucency)
  color = colors.with_alpha(colors.bar.bg, 0.2),
  blur_radius = 20,
  padding_right = 2,
  padding_left = 2,
})
