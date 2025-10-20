local colors = require("colors")
local settings = require("settings")
local popup = require("helpers.popup")

local cache_dir = os.getenv("HOME") .. "/.cache/sketchybar"
local weather_cache = cache_dir .. "/weather.txt"
local location_cache = cache_dir .. "/location.txt"

local popup_width = 250
local weather_cache_ttl = 300     -- 5 minutes
local location_cache_ttl = 3600   -- 1 hour

-- Ensure cache dir exists
sbar.exec("/bin/zsh -lc 'mkdir -p " .. cache_dir .. "'")

local function trim_newline(s)
  if not s then return "" end
  return (s:gsub("\n$", ""))
end

-- Split function to properly handle empty fields
local function split(s, sep)
  local parts = {}
  if sep == nil or sep == "%s" then
    for w in s:gmatch("%S+") do parts[#parts+1] = w end
    return parts
  end
  -- Escape any non-alphanumeric char for Lua pattern
  local escaped_sep = sep:gsub("(%W)", "%%%1")
  local pattern = "(.-)" .. escaped_sep
  local tmp = s .. sep
  for m in tmp:gmatch(pattern) do parts[#parts+1] = m end
  return parts
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_file(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

-- Simple shell exec wrapper
local function exec(cmd, callback)
  sbar.exec(cmd, callback)
end

local function owm_icon_for(id, is_day)
  id = tonumber(id) or 800
  if id >= 200 and id < 300 then return "⛈️" end            -- Thunderstorm
  if id >= 300 and id < 400 then return "🌦️" end            -- Drizzle
  if id >= 500 and id < 600 then return "🌧️" end            -- Rain
  if id >= 600 and id < 700 then return "❄️" end            -- Snow
  if id >= 700 and id < 800 then return "🌫️" end            -- Atmosphere
  if id == 800 then return is_day and "☀️" or "🌙" end      -- Clear
  if id == 801 then return "🌤" end                         -- Few clouds
  if id == 802 or id == 803 then return "⛅" end            -- Scattered/broken
  return "☁️"                                               -- Default
end

local function parse_weather_psv(psv)
  local parts = split(psv or "", "|")
  if #parts < 10 then return nil end
  return {
    temp = tonumber(parts[1] or 0),
    id = tonumber(parts[2] or 800),
    desc = parts[3] or "",
    sunrise = tonumber(parts[4] or 0),
    sunset = tonumber(parts[5] or 0),
    tz = parts[6] or "",
    wind = tonumber(parts[7] or 0),
    humidity = tonumber(parts[8] or 0),
    pressure = tonumber(parts[9] or 0),
    feels = tonumber(parts[10] or 0),
  }
end

local function build_onecall_url(lat, lon, key)
  return string.format(
    "https://api.openweathermap.org/data/3.0/onecall?lat=%s&lon=%s&exclude=minutely,hourly,daily,alerts&units=metric&lang=zh_cn&appid=%s",
    lat, lon, key
  )
end

local function build_jxa_cmd(js_lines, argv)
  local parts = {}
  for _, line in ipairs(js_lines) do
    parts[#parts+1] = "-e " .. string.format("%q", line)
  end
  local cmd = "/usr/bin/osascript -l JavaScript " .. table.concat(parts, " ")
  if argv then cmd = cmd .. " -- " .. string.format("%q", argv) end
  return cmd
end

local function jxa_fetch_onecall(url)
  local js_lines = {
    "function run(argv) {",
    "  var url = argv[0];",
    "  var app = Application.currentApplication();",
    "  app.includeStandardAdditions = true;",
    "  var s = app.doShellScript(\"/usr/bin/curl -m 6 -s \" + JSON.stringify(url));",
    "  var j = JSON.parse(s);",
    "  var c = j.current || {};",
    "  var w = (c.weather && c.weather[0]) || {};",
    "  return [",
    "    Math.round((c.temp||0)),",
    "    (w.id||800),",
    "    (w.description||\"\"),",
    "    (c.sunrise||0),",
    "    (c.sunset||0),",
    "    (j.timezone||\"\"),",
    "    (+(Math.round(((c.wind_speed||0)*10))/10)).toFixed(1),",
    "    (c.humidity||0),",
    "    (c.pressure||0),",
    "    Math.round((c.feels_like||0))",
    "  ].join(\"|\");",
    "}"
  }
  return build_jxa_cmd(js_lines, url)
end

local function get_api_key(callback)
  local cmd = [[/bin/zsh -lc "security find-generic-password -a "$USER" -s OPENWEATHERMAP_API_KEY -w 2>/dev/null || true"]]
  sbar.exec(cmd, function(out)
    local key = trim_newline(out or "")
    callback(key ~= "" and key or nil)
  end)
end

local function get_location_label(callback)
  -- Get ipinfo city/country (fast, no JSON parsing needed except separate calls)
  sbar.exec("/bin/zsh -lc 'curl -m 2 -s https://ipinfo.io/city'", function(city)
    city = trim_newline(city)
    sbar.exec("/bin/zsh -lc 'curl -m 2 -s https://ipinfo.io/country'", function(country)
      country = trim_newline(country)
      if city ~= "" and country ~= "" then
        callback(city .. ", " .. country)
      elseif city ~= "" then
        callback(city)
      else
        callback(nil)
      end
    end)
  end)
end

local function resolve_location(callback)
  -- Check cache first
  local cached = read_file(location_cache)
  local now = os.time()
  if cached and cached ~= "" then
    local parts = split(trim_newline(cached), "|")
    if #parts >= 4 then
      local ts = tonumber(parts[1] or 0) or 0
      if now - ts < location_cache_ttl then
        return callback({ lat = parts[2], lon = parts[3], label = parts[4] })
      end
    end
  end

  -- Use native CoreLocation helper (first run may prompt for permission)
  local base = os.getenv("HOME") .. "/.config/sketchybar/helpers/event_providers/location/bin/location"
  local cmd = "/bin/zsh -lc '" .. base .. " 2>/dev/null | head -n1'"
  exec(cmd, function(out)
    local loc = trim_newline(out or "")
    if loc ~= "" and loc:find(",", 1, true) then
      local lat, lon = table.unpack(split(loc, ","))
      get_location_label(function(label)
        label = label or ""
        write_file(location_cache, string.format("%d|%s|%s|%s", os.time(), lat, lon, label))
        callback({ lat = lat, lon = lon, label = label })
      end)
    else
      callback(nil)
    end
  end)
end

local weather = sbar.add("item", "widgets.weather", {
  position = "right",
  icon = {
    string = "🌡",
    align = "left",
    color = colors.white,
    font = {
      style = settings.font.style_map["Regular"],
      size = 14.0,
    },
  },
  label = {
    string = "??°",
    align = "left",
    width = 34,
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Regular"],
      size = 14.0,
    },
  },
})

local weather_bracket = sbar.add("bracket", "widgets.weather.bracket", {
  weather.name,
}, {
  background = { color = colors.bg1 },
  popup = { align = "center" }
})

popup.register(weather_bracket)

sbar.add("item", { position = "right", width = settings.group_paddings })

-- Popup items
local left_col_w = math.floor(popup_width * 0.55)
local right_col_w = popup_width - left_col_w

local location_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { string = "📍", align = "left", width = left_col_w },
  label = { string = "—", align = "right", width = right_col_w },
})

local summary_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { string = "☁️", align = "left", width = left_col_w },
  label = { string = "—", align = "right", width = right_col_w },
})

local separator_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { drawing = false },
  label = { drawing = false },
  background = { color = colors.grey, height = 1, y_offset = -8 },
})

local humidity_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { string = "💧", align = "left", width = left_col_w },
  label = { string = "—", align = "right", width = right_col_w },
})

local wind_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { string = "💨", align = "left", width = left_col_w },
  label = { string = "—", align = "right", width = right_col_w },
})

local pressure_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { string = "🔵", align = "left", width = left_col_w },
  label = { string = "—", align = "right", width = right_col_w },
})

local current_data = nil
local current_location_label = nil

local function update_popup_contents()
  if not current_data then return end
  local desc = current_data.desc or ""
  local line1 = string.format("%s°C  (feels like %s°C)  %s", math.floor(current_data.temp + 0.5), math.floor(current_data.feels + 0.5), desc)
  summary_item:set({ label = line1 })
  location_item:set({ label = current_location_label or (current_data.tz or "") })
  humidity_item:set({ label = tostring(current_data.humidity) .. "%" })
  wind_item:set({ label = string.format("%.1f m/s", current_data.wind or 0) })
  pressure_item:set({ label = tostring(current_data.pressure) .. " hPa" })
end

local function apply_weather_to_ui(data)
  current_data = data
  local now = os.time()
  local is_day = (now >= (data.sunrise or 0)) and (now < (data.sunset or 0))
  local icon = owm_icon_for(data.id, is_day)
  local temp_str = tostring(math.floor((data.temp or 0) + 0.5)) .. "°"
  weather:set({ icon = { string = icon, color = colors.white }, label = temp_str })
  update_popup_contents()
end

-- Fix 2a: Correct write_weather_cache to include lat/lon
local function write_weather_cache(data)
  local ts = os.time()
  local line = table.concat({
    ts,
    tostring(math.floor((data.temp or 0) + 0.5)),
    tostring(data.id or 800),
    data.desc or "",
    tostring(data.sunrise or 0),
    tostring(data.sunset or 0),
    data.tz or "",
    string.format("%.1f", data.wind or 0),
    tostring(data.humidity or 0),
    tostring(data.pressure or 0),
    tostring(math.floor((data.feels or 0) + 0.5)),
    -- Added: store location info for right-click use
    tostring(data.lat or 0),
    tostring(data.lon or 0)
  }, "|")
  write_file(weather_cache, line)
end

-- Fix 2b: Correct try_read_weather_cache to read lat/lon
local function try_read_weather_cache()
  local cached = read_file(weather_cache)
  if not cached or cached == "" then return nil end
  local parts = split(trim_newline(cached), "|")
  -- Changed: now must be 13 fields (ts + 10 data + lat + lon)
  if #parts < 13 then return nil end
  local ts = tonumber(parts[1] or 0) or 0
  if os.time() - ts >= weather_cache_ttl then return nil end
  
  -- Rebuild psv of 10 weather fields (parts 2-11)
  local p = {}
  -- Changed: loop to 11 (the 10th data field)
  for i = 2, 11 do p[#p+1] = parts[i] end
  local data = parse_weather_psv(table.concat(p, "|"))
  
  if not data then return nil end
  
  -- Added: reattach lat/lon to cached object
  data.lat = parts[12]
  data.lon = parts[13]
  
  return data
end

local function do_fetch(lat, lon, api_key)
  local url = build_onecall_url(lat, lon, api_key)
  exec(jxa_fetch_onecall(url), function(out)
    out = trim_newline(out or "")
    local data = parse_weather_psv(out)
    if not data then return end
    data.lat = lat
    data.lon = lon
    if not current_location_label or current_location_label == "" then
      -- if no label, fall back to timezone
      current_location_label = data.tz or current_location_label
    end
    write_weather_cache(data)
    apply_weather_to_ui(data)
  end)
end

local function refresh(force)
  if not force then
    local cached = try_read_weather_cache()
    if cached then
      current_data = cached
      -- Use cached location label if available
      local loc_cached = read_file(location_cache)
      if loc_cached and loc_cached ~= "" then
        local parts = split(trim_newline(loc_cached), "|")
        if #parts >= 4 then current_location_label = parts[4] end
      end
      apply_weather_to_ui(cached)
      return
    end
  end

  get_api_key(function(key)
    if not key then
      weather:set({ icon = { string = "⚠️", color = colors.red } })
      weather:set({ label = "API" })
      return
    end
    resolve_location(function(loc)
      if not loc then
        weather:set({ icon = { string = "⚠️", color = colors.red } })
        weather:set({ label = "LOC" })
        return
      end
      current_location_label = (loc.label ~= "" and loc.label or nil)
      do_fetch(loc.lat, loc.lon, key)
    end)
  end)
end

-- Click handlers
local function on_click(env)
  if env.BUTTON == "right" then
    local lat = current_data and current_data.lat or nil
    local lon = current_data and current_data.lon or nil
    if lat and lon then
      local map_url = "https://openweathermap.org/weathermap?basemap=map&cities=true&layer=temperature&lat=" .. lat .. "&lon=" .. lon .. "&zoom=10"
      exec("open \"" .. map_url .. "\"")
    else
    exec("open -a \"Weather\"")
    end
    return
  end
  if env.BUTTON == "middle" then
    -- Force refresh: drop caches
    sbar.exec("/bin/zsh -lc 'rm -f " .. weather_cache .. " " .. location_cache .. "'", function()
      refresh(true)
    end)
    return
  end
  -- left click: toggle popup; fill contents on show
  popup.toggle(weather_bracket, update_popup_contents)
end

weather:subscribe("mouse.clicked", on_click)
weather_bracket:subscribe("mouse.exited.global", function(_) popup.hide(weather_bracket) end)

-- Periodic updates and initial paint
-- Update once per 5 minutes (300s) to align with cache TTL and avoid spam
weather:set({ updates = true, update_freq = 300 })

weather:subscribe("routine", function(_) refresh(false) end)

refresh(false)
