return {
  paddings = 3,
  group_paddings = 5,

  icons = "sf-symbols", -- available: NerdFont, sf-symbols

  -- Shortcuts (right-side compact icon chunk)
  shortcuts_icon_size = 15.0,

  -- Text uses Sarasa Term SC; icons stay on Nerd Font for glyph coverage.
  font = {
    text = "Sarasa Term SC", -- Used for text
    numbers = "Sarasa Term SC", -- Used for numbers
    icons = "JetBrainsMono Nerd Font Mono", -- Used for icons (NerdFont glyphs)
    -- Match the font members exposed by macOS for the installed Sarasa Term SC family.
    style_map = {
      ["Regular"] = "Regular",
      ["Semibold"] = "SemiBold",
      ["Bold"] = "Bold",
      ["Heavy"] = "Bold",
      ["Black"] = "Bold",
    },
  },
}
