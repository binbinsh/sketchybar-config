local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")
local icons = require("icons")

local cache_dir = os.getenv("HOME") .. "/.cache/sketchybar"
local weather_cache = cache_dir .. "/weather.txt"
local location_cache = cache_dir .. "/location.txt"

local popup_width = 250
local weather_cache_ttl = 600    -- 10 minutes
local location_cache_ttl = 1800   -- 30 minutes

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

-- Use rotating SF Symbol for manual refresh animation
local update_popup_contents
local title_item


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

-- Reverse geocode coordinates to a human-friendly place name using
-- OpenStreetMap Nominatim (no API key required). We parse JSON via JXA.
local function reverse_geocode_label(lat, lon, callback)
  local url = string.format(
    "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=%s&lon=%s&zoom=12&addressdetails=1",
    lat, lon
  )
  local js_lines = {
    "function run(argv) {",
    "  var url = argv[0];",
    "  var app = Application.currentApplication();",
    "  app.includeStandardAdditions = true;",
    "  var cmd = '/usr/bin/curl -m 4 -H ' + JSON.stringify('User-Agent: sketchybar-weather') + ' -s ' + JSON.stringify(url);",
    "  var s = app.doShellScript(cmd);",
    "  try {",
    "    var j = JSON.parse(s);",
    "    var a = j.address || {};",
    "    var label = a.neighbourhood || a.suburb || a.quarter || a.residential || a.hamlet || a.village || a.town || a.city_district || a.district || a.city || a.county || a.state || a.country || '';",
    "    if (!label && j.name) label = j.name;",
    "    if (!label && j.display_name) label = (j.display_name.split(',')[0]||'').trim();",
    "    return label;",
    "  } catch (e) { return ''; }",
    "}"
  }
  exec(build_jxa_cmd(js_lines, url), function(out)
    out = trim_newline(out or "")
    callback(out ~= "" and out or nil)
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

  -- Launch the .app (blocks until exit), then read cache file directly
  local app_bundle = os.getenv("HOME") .. "/.config/sketchybar/helpers/location/bin/SketchyBarLocationHelper.app"
  local cmd = "/bin/zsh -lc 'open -W " .. app_bundle .. " >/dev/null 2>&1'"
  exec(cmd, function(_)
    local raw = read_file(location_cache)
    raw = trim_newline(raw or "")
    local parts = split(raw, "|")
    if #parts >= 3 then
      local lat = parts[2]
      local lon = parts[3]
      reverse_geocode_label(lat, lon, function(label)
        if not label or label == "" then label = "" end
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
    string = "☁️",
    align = "left",
    color = colors.white,
    y_offset = 2,
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

center_popup.register(weather_bracket)

sbar.add("item", { position = "right", width = settings.group_paddings })

-- Popup items
local left_col_w = math.floor(popup_width * 0.55)
local right_col_w = popup_width - left_col_w

-- Title row (centered) like Wi‑Fi popup title
local title_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = {
    font = { style = settings.font.style_map["Bold"] },
    string = "📍",
  },
  width = popup_width,
  align = "center",
  label = {
    font = { family = settings.font.icons, size = 15, style = settings.font.style_map["Bold"] },
    string = "—",
  },
  background = { height = 2, color = colors.grey, y_offset = -15 },
})

-- Detail rows: English text on the left, value on the right
local cond_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Condition:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local temp_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Temperature:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local feels_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Feels like:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local humidity_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Humidity:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local wind_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Wind:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local pressure_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Pressure:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local tz_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Time zone:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local sunrise_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Sunrise:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local sunset_item = sbar.add("item", {
  position = "popup." .. weather_bracket.name,
  icon = { align = "left", string = "Sunset:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

local current_data = nil
local current_location_label = nil

local function update_popup_contents()
  if not current_data then return end
  local name = current_location_label
  local latn = tonumber(current_data.lat or "")
  local lonn = tonumber(current_data.lon or "")
  local coord_text = ""
  if latn and lonn then
    local lat_i = select(1, math.modf(latn))
    local lon_i = select(1, math.modf(lonn))
    coord_text = string.format("(%d, %d)", lat_i, lon_i)
  end
  local title_text
  if name and name ~= "" then
    title_text = coord_text ~= "" and (name .. " " .. coord_text) or name
  else
    title_text = coord_text ~= "" and coord_text or "Location"
  end
  title_item:set({ label = title_text .. " " .. icons.refresh })
  cond_item:set({ label = current_data.desc or "" })
  temp_item:set({ label = tostring(math.floor((current_data.temp or 0) + 0.5)) .. "°C" })
  feels_item:set({ label = tostring(math.floor((current_data.feels or 0) + 0.5)) .. "°C" })
  humidity_item:set({ label = tostring(current_data.humidity or 0) .. "%" })
  wind_item:set({ label = string.format("%.1f m/s", current_data.wind or 0) })
  pressure_item:set({ label = tostring(current_data.pressure or 0) .. " hPa" })
  tz_item:set({ label = current_data.tz or "" })
  local sr = tonumber(current_data.sunrise or 0)
  local ss = tonumber(current_data.sunset or 0)
  if sr and sr > 0 then sunrise_item:set({ label = os.date("%H:%M", sr) }) end
  if ss and ss > 0 then sunset_item:set({ label = os.date("%H:%M", ss) }) end
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
  -- left click: toggle popup; fill contents on show
  center_popup.toggle(weather_bracket, update_popup_contents)
end

weather:subscribe("mouse.clicked", on_click)
title_item:subscribe("mouse.clicked", function(_)
  -- Clear caches and clear popup contents immediately
  cond_item:set({ label = "—" })
  temp_item:set({ label = "—" })
  feels_item:set({ label = "—" })
  humidity_item:set({ label = "—" })
  wind_item:set({ label = "—" })
  pressure_item:set({ label = "—" })
  tz_item:set({ label = "—" })
  sunrise_item:set({ label = "—" })
  sunset_item:set({ label = "—" })
  title_item:set({ label = (current_location_label or "—") .. " " .. icons.refresh })
  current_data = nil
  sbar.exec("/bin/zsh -lc 'rm -f " .. weather_cache .. " " .. location_cache .. "'", function()
    refresh(true)
  end)
end)
center_popup.auto_hide(weather_bracket, weather)

-- Periodic updates and initial paint (hourly)
weather:set({ updates = true, update_freq = weather_cache_ttl })

weather:subscribe("routine", function(_) refresh(false) end)

refresh(true)
