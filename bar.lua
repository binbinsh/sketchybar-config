local colors = require("colors")

-- Equivalent to the --bar domain
sbar.bar({
  height = 32,
  topmost = true,
  color = colors.bar.bg,
  padding_right = 2,
  padding_left = 2,
})
