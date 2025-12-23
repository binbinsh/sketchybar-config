local icons = require("icons")
local colors = require("colors")

local whitelist = { ["Spotify"] = true,
                    ["Music"] = true,
                    ["YouTube Music"] = true };

-- Start native now playing provider: now_playing <event-name>
sbar.exec("killall now_playing >/dev/null 2>&1; $CONFIG_DIR/helpers/now_playing/bin/now_playing media_nowplaying &")

-- Ensure event exists for manual triggers and extension bridge
sbar.add("event", "media_nowplaying")


local media_cover = sbar.add("item", {
  position = "right",
  background = {
    image = {
      string = "media.artwork",
      scale = 0.85,
    },
    color = colors.transparent,
  },
  label = { drawing = false },
  icon = { drawing = false },
  drawing = false,
  updates = true,
  popup = {
    align = "center",
    horizontal = true,
  }
})

local media_artist = sbar.add("item", {
  position = "right",
  drawing = false,
  padding_left = 3,
  padding_right = 0,
  width = 0,
  icon = { drawing = false },
  label = {
    width = 0,
    font = { size = 9 },
    color = colors.with_alpha(colors.white, 0.6),
    max_chars = 18,
    y_offset = 6,
  },
})

local media_title = sbar.add("item", {
  position = "right",
  drawing = false,
  padding_left = 3,
  padding_right = 0,
  icon = { drawing = false },
  label = {
    font = { size = 11 },
    width = 0,
    max_chars = 16,
    y_offset = -5,
  },
})

sbar.add("item", {
  position = "popup." .. media_cover.name,
  icon = { string = icons.media.back },
  label = { drawing = false },
  click_script = "$CONFIG_DIR/helpers/now_playing/bin/now_playing previous",
})
sbar.add("item", {
  position = "popup." .. media_cover.name,
  icon = { string = icons.media.play_pause },
  label = { drawing = false },
  click_script = "$CONFIG_DIR/helpers/now_playing/bin/now_playing toggle",
})
sbar.add("item", {
  position = "popup." .. media_cover.name,
  icon = { string = icons.media.forward },
  label = { drawing = false },
  click_script = "$CONFIG_DIR/helpers/now_playing/bin/now_playing next",
})

local interrupt = 0
local last = { title = "", artist = "", state = "" }
local animate_detail

local function maybe_expand_and_schedule(title, artist, state)
  local track_changed = (title ~= last.title) or (artist ~= last.artist)
  local resumed = (last.state ~= "playing" and state == "playing")
  if track_changed or resumed then
    animate_detail(true)
    interrupt = 1
    sbar.delay(5, function() animate_detail(false) end)
  end
  last.title, last.artist, last.state = title, artist, state
end
animate_detail = function(detail)
  if (not detail) then interrupt = interrupt - 1 end
  if interrupt > 0 and (not detail) then return end

  sbar.animate("tanh", 30, function()
    media_artist:set({ label = { width = detail and "dynamic" or 0 } })
    media_title:set({ label = { width = detail and "dynamic" or 0 } })
  end)
end

media_cover:subscribe("media_change", function(env)
  if whitelist[env.INFO.app] then
    local drawing = (env.INFO.state == "playing")
    media_artist:set({ drawing = drawing, label = env.INFO.artist, })
    media_title:set({ drawing = drawing, label = env.INFO.title, })
    media_cover:set({ drawing = drawing })

    if drawing then
      maybe_expand_and_schedule(env.INFO.title or "", env.INFO.artist or "", env.INFO.state or "")
    else
      media_cover:set({ popup = { drawing = false } })
    end
  end
end)

-- Fallback/alternative source via native helper (Brave/Chrome PWAs etc.)
media_cover:subscribe("media_nowplaying", function(env)
  local title = env.title or ""
  local artist = env.artist or ""
  local state = env.state or ((title ~= "" or artist ~= "") and "playing" or "paused")
  local app = env.app or ""
  local drawing = (title ~= "" or artist ~= "") and (state ~= "paused")

  media_artist:set({ drawing = drawing, label = artist })
  media_title:set({ drawing = drawing, label = title })
  media_cover:set({ drawing = drawing })

  if drawing then
    maybe_expand_and_schedule(title, artist, state)
  else
    media_cover:set({ popup = { drawing = false } })
  end

  -- Optionally use helper-provided artwork file
  -- if env.artwork_path and env.artwork_path ~= "" then
  --   media_cover:set({ background = { image = { string = env.artwork_path, scale = 0.85 } } })
  -- end
end)

media_cover:subscribe("mouse.entered", function(env)
  interrupt = interrupt + 1
  animate_detail(true)
end)

media_cover:subscribe("mouse.exited", function(env)
  animate_detail(false)
end)

media_cover:subscribe("mouse.clicked", function(env)
  media_cover:set({ popup = { drawing = "toggle" }})
end)

media_title:subscribe("mouse.exited.global", function(env)
  media_cover:set({ popup = { drawing = false }})
end)
