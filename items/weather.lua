local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

-- Battery-style weather widget:
-- - Compact item (no brackets/padding items)
-- - Event-driven refresh + TTL cache
-- - Popup uses battery-style rows and only updates when shown
-- - Temperature is always displayed as °C

local cache_dir = os.getenv("HOME") .. "/.cache/sketchybar"
local weather_cache = cache_dir .. "/weather.txt"
local location_cache = cache_dir .. "/location.txt"

local WEATHER_TTL = tonumber(os.getenv("WEATHER_CACHE_TTL")) or 600
local LOCATION_TTL = tonumber(os.getenv("WEATHER_LOCATION_TTL")) or 1800

-- Best-effort: ensure cache dir exists (silent).
sbar.exec("/bin/zsh -lc 'mkdir -p " .. cache_dir .. " >/dev/null 2>&1'")

local function trim_newline(s)
  if not s then return "" end
  return (tostring(s):gsub("\n$", ""))
end

-- Split function that preserves empty fields when using a non-whitespace separator.
local function split(s, sep)
  local parts = {}
  s = tostring(s or "")
  if sep == nil or sep == "%s" then
    for w in s:gmatch("%S+") do parts[#parts + 1] = w end
    return parts
  end
  local escaped_sep = sep:gsub("(%W)", "%%%1")
  local pattern = "(.-)" .. escaped_sep
  local tmp = s .. sep
  for m in tmp:gmatch(pattern) do parts[#parts + 1] = m end
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

local function sanitize_field(s)
  s = tostring(s or "")
  return s:gsub("\n", " "):gsub("|", "/")
end

local function round_int(n)
  n = tonumber(n) or 0
  if n >= 0 then return math.floor(n + 0.5) end
  return math.ceil(n - 0.5)
end

local function format_temp_c(n)
  return tostring(round_int(n)) .. "°C"
end

local function format_wind(n)
  local v = tonumber(n)
  if v == nil then return "-" end
  return string.format("%.1f m/s", v)
end

local function format_humidity(n)
  local v = tonumber(n)
  if v == nil then return "-" end
  return tostring(round_int(v)) .. "%"
end

local function format_pressure(n)
  local v = tonumber(n)
  if v == nil then return "-" end
  return tostring(round_int(v)) .. " hPa"
end

local function format_time_local(epoch, tz_offset)
  local t = tonumber(epoch) or 0
  if t <= 0 then return "-" end
  local off = tonumber(tz_offset) or 0
  -- OpenWeather timestamps are UTC; display in the location's local time.
  return os.date("!%H:%M", t + off)
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

local function owm_zh_for(id)
  id = tonumber(id) or 800
  if id >= 200 and id < 300 then return "雷暴" end
  if id >= 300 and id < 400 then return "毛毛雨" end
  if id >= 500 and id < 600 then return "降雨" end
  if id >= 600 and id < 700 then return "降雪" end
  if id >= 700 and id < 800 then
    local map = {
      [701] = "薄雾",
      [711] = "烟雾",
      [721] = "霾",
      [731] = "沙尘",
      [741] = "雾",
      [751] = "沙尘",
      [761] = "扬尘",
      [762] = "火山灰",
      [771] = "狂风",
      [781] = "龙卷风",
    }
    return map[id] or "雾霾"
  end
  if id == 800 then return "晴" end
  if id == 801 then return "少云" end
  if id == 802 then return "多云" end
  if id == 803 or id == 804 then return "阴" end
  return nil
end

local function build_weather_url(lat, lon, key)
  return string.format(
    "https://api.openweathermap.org/data/3.0/onecall?lat=%s&lon=%s&units=metric&lang=en&appid=%s",
    lat, lon, key
  )
end

local function build_jxa_cmd(js_lines, argv)
  local parts = {}
  for _, line in ipairs(js_lines) do
    parts[#parts + 1] = "-e " .. string.format("%q", line)
  end
  local cmd = "/usr/bin/osascript -l JavaScript " .. table.concat(parts, " ")
  if argv then cmd = cmd .. " -- " .. string.format("%q", argv) end
  return cmd
end

-- Reverse geocode coordinates to a human-friendly place name (no API key).
-- Cached via `location_cache` to keep this lightweight.
local function reverse_geocode_label(lat, lon, callback)
  local url = string.format(
    "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=%s&lon=%s&zoom=12&addressdetails=1&accept-language=zh-CN",
    lat,
    lon
  )

  local js_lines = {
    "function run(argv) {",
    "  var url = argv[0];",
    "  var app = Application.currentApplication();",
    "  app.includeStandardAdditions = true;",
    "  var cmd = '/usr/bin/curl -m 4 -H ' + JSON.stringify('User-Agent: sketchybar-weather') + ' -H ' + JSON.stringify('Accept-Language: zh-CN,zh;q=0.9,en;q=0.6') + ' -s ' + JSON.stringify(url);",
    "  var s = app.doShellScript(cmd);",
    "  try {",
    "    var j = JSON.parse(s);",
    "    var a = j.address || {};",
    "    var label = a.neighbourhood || a.suburb || a.quarter || a.residential || a.hamlet || a.village || a.town || a.city_district || a.district || a.city || a.county || a.state || a.country || '';",
    "    if (!label && j.name) label = j.name;",
    "    if (!label && j.display_name) label = (j.display_name.split(',')[0]||'').trim();",
    "    return label;",
    "  } catch (e) { return ''; }",
    "}",
  }

  sbar.exec(build_jxa_cmd(js_lines, url), function(out)
    out = trim_newline(out or "")
    if callback then callback(out ~= "" and out or nil) end
  end)
end

local function jxa_fetch_onecall(url)
  local js_lines = {
    "function run(argv) {",
    "  var url = argv[0];",
    "  var app = Application.currentApplication();",
    "  app.includeStandardAdditions = true;",
    "  try {",
    "    var s = app.doShellScript('/usr/bin/curl -m 10 -s ' + JSON.stringify(url));",
    "    var j = JSON.parse(s);",
    "    if (j.cod && j.cod != 200 && j.cod != '200') return '';",
    "    var c = j.current || {};",
    "    var w = (c.weather && c.weather[0]) || {};",
    "    var hourly = j.hourly || [];",
    "    var daily = j.daily || [];",
    "    var alerts = j.alerts || [];",
    "    var hourlyTemps = [];",
    "    for (var i = 0; i < 24 && i < hourly.length; i++) {",
    "      hourlyTemps.push(Math.round(hourly[i].temp || 0));",
    "    }",
    "    var dailyData = [];",
    "    for (var i = 0; i < 5 && i < daily.length; i++) {",
    "      var d = daily[i];",
    "      var dw = (d.weather && d.weather[0]) || {};",
    "      dailyData.push({",
    "        dt: d.dt || 0,",
    "        temp_min: Math.round((d.temp && d.temp.min) || 0),",
    "        temp_max: Math.round((d.temp && d.temp.max) || 0),",
    "        weather_id: dw.id || 800,",
    "        pop: d.pop || 0",
    "      });",
    "    }",
    "    var alertData = [];",
    "    for (var i = 0; i < alerts.length; i++) {",
    "      alertData.push({ event: alerts[i].event || 'Weather Alert' });",
    "    }",
    "    return [",
    "      Math.round((c.temp||0)),",
    "      (w.id||800),",
    "      (w.description||''),",
    "      (c.sunrise||0),",
    "      (c.sunset||0),",
    "      (j.timezone_offset||0),",
    "      (+(Math.round(((c.wind_speed||0)*10))/10)).toFixed(1),",
    "      (c.humidity||0),",
    "      (c.pressure||0),",
    "      Math.round((c.feels_like||0)),",
    "      '',",
    "      JSON.stringify(hourlyTemps),",
    "      JSON.stringify(dailyData),",
    "      JSON.stringify(alertData)",
    "    ].join('|');",
    "  } catch (e) { return ''; }",
    "}",
  }
  return build_jxa_cmd(js_lines, url)
end

local function safe_json_decode(str)
  if not str or str == "" then return nil end
  local ok, result = pcall(function()
    -- Simple JSON array/object parser for our limited use case
    local fn = load("return " .. str:gsub("%[", "{"):gsub("%]", "}"):gsub(":", "="):gsub('"(%w+)"=', "%1="))
    if fn then return fn() end
    return nil
  end)
  return ok and result or nil
end

local function parse_weather_psv(psv)
  local parts = split(psv or "", "|")
  if #parts < 11 then return nil end

  -- Parse hourly temps (JSON array of numbers)
  local hourly_temps = nil
  if parts[12] and parts[12] ~= "" then
    local temps_str = parts[12]
    hourly_temps = {}
    for num in temps_str:gmatch("%-?%d+") do
      hourly_temps[#hourly_temps + 1] = tonumber(num)
    end
    if #hourly_temps == 0 then hourly_temps = nil end
  end

  -- Parse daily forecast (JSON array of objects)
  local daily = nil
  if parts[13] and parts[13] ~= "" then
    daily = {}
    -- Parse JSON manually: {"dt":123,"temp_min":10,"temp_max":20,"weather_id":800,"pop":0.1}
    for obj in parts[13]:gmatch("{[^}]+}") do
      local dt = tonumber(obj:match('"dt":(%d+)'))
      local temp_min = tonumber(obj:match('"temp_min":(%-?%d+)'))
      local temp_max = tonumber(obj:match('"temp_max":(%-?%d+)'))
      local weather_id = tonumber(obj:match('"weather_id":(%d+)'))
      local pop = tonumber(obj:match('"pop":([%d%.]+)'))
      if dt then
        daily[#daily + 1] = {
          dt = dt,
          temp_min = temp_min or 0,
          temp_max = temp_max or 0,
          weather_id = weather_id or 800,
          pop = pop or 0,
        }
      end
    end
    if #daily == 0 then daily = nil end
  end

  -- Parse alerts (JSON array of objects with event field)
  local alerts = nil
  if parts[14] and parts[14] ~= "" and parts[14] ~= "[]" then
    alerts = {}
    for event in parts[14]:gmatch('"event":"([^"]*)"') do
      alerts[#alerts + 1] = { event = event }
    end
    if #alerts == 0 then alerts = nil end
  end

  return {
    temp = tonumber(parts[1] or 0),
    id = tonumber(parts[2] or 800),
    desc = parts[3] or "",
    sunrise = tonumber(parts[4] or 0),
    sunset = tonumber(parts[5] or 0),
    tz_offset = tonumber(parts[6] or 0),
    wind = tonumber(parts[7] or 0),
    humidity = tonumber(parts[8] or 0),
    pressure = tonumber(parts[9] or 0),
    feels = tonumber(parts[10] or 0),
    place = parts[11] or "",
    hourly_temps = hourly_temps,
    daily = daily,
    alerts = alerts,
  }
end

local function write_weather_cache(data)
  if type(data) ~= "table" then return end
  local ts = os.time()

  -- Serialize hourly_temps as JSON array
  local hourly_json = "[]"
  if data.hourly_temps and #data.hourly_temps > 0 then
    hourly_json = "[" .. table.concat(data.hourly_temps, ",") .. "]"
  end

  -- Serialize daily as JSON array
  local daily_json = "[]"
  if data.daily and #data.daily > 0 then
    local daily_parts = {}
    for _, d in ipairs(data.daily) do
      daily_parts[#daily_parts + 1] = string.format(
        '{"dt":%d,"temp_min":%d,"temp_max":%d,"weather_id":%d,"pop":%.2f}',
        d.dt or 0, d.temp_min or 0, d.temp_max or 0, d.weather_id or 800, d.pop or 0
      )
    end
    daily_json = "[" .. table.concat(daily_parts, ",") .. "]"
  end

  -- Serialize alerts as JSON array
  local alerts_json = "[]"
  if data.alerts and #data.alerts > 0 then
    local alert_parts = {}
    for _, a in ipairs(data.alerts) do
      alert_parts[#alert_parts + 1] = string.format('{"event":"%s"}', sanitize_field(a.event or ""))
    end
    alerts_json = "[" .. table.concat(alert_parts, ",") .. "]"
  end

  local line = table.concat({
    tostring(ts),
    tostring(round_int(data.temp)),
    tostring(data.id or 800),
    sanitize_field(data.desc),
    tostring(data.sunrise or 0),
    tostring(data.sunset or 0),
    tostring(data.tz_offset or 0),
    string.format("%.1f", tonumber(data.wind) or 0),
    tostring(data.humidity or 0),
    tostring(data.pressure or 0),
    tostring(round_int(data.feels or 0)),
    sanitize_field(data.place),
    tostring(data.lat or 0),
    tostring(data.lon or 0),
    hourly_json,
    daily_json,
    alerts_json,
  }, "|")
  write_file(weather_cache, line)
end

local function try_read_weather_cache()
  local cached = read_file(weather_cache)
  if not cached or cached == "" then return nil end
  local parts = split(trim_newline(cached), "|")
  if #parts < 14 then return nil end

  local ts = tonumber(parts[1] or 0) or 0
  if ts <= 0 then return nil end
  if os.time() - ts >= WEATHER_TTL then return nil end

  -- Parse hourly temps
  local hourly_temps = nil
  if parts[15] and parts[15] ~= "" and parts[15] ~= "[]" then
    hourly_temps = {}
    for num in parts[15]:gmatch("%-?%d+") do
      hourly_temps[#hourly_temps + 1] = tonumber(num)
    end
    if #hourly_temps == 0 then hourly_temps = nil end
  end

  -- Parse daily forecast
  local daily = nil
  if parts[16] and parts[16] ~= "" and parts[16] ~= "[]" then
    daily = {}
    for obj in parts[16]:gmatch("{[^}]+}") do
      local dt = tonumber(obj:match('"dt":(%d+)'))
      local temp_min = tonumber(obj:match('"temp_min":(%-?%d+)'))
      local temp_max = tonumber(obj:match('"temp_max":(%-?%d+)'))
      local weather_id = tonumber(obj:match('"weather_id":(%d+)'))
      local pop = tonumber(obj:match('"pop":([%d%.]+)'))
      if dt then
        daily[#daily + 1] = {
          dt = dt,
          temp_min = temp_min or 0,
          temp_max = temp_max or 0,
          weather_id = weather_id or 800,
          pop = pop or 0,
        }
      end
    end
    if #daily == 0 then daily = nil end
  end

  -- Parse alerts
  local alerts = nil
  if parts[17] and parts[17] ~= "" and parts[17] ~= "[]" then
    alerts = {}
    for event in parts[17]:gmatch('"event":"([^"]*)"') do
      alerts[#alerts + 1] = { event = event }
    end
    if #alerts == 0 then alerts = nil end
  end

  return {
    ts = ts,
    temp = tonumber(parts[2] or 0),
    id = tonumber(parts[3] or 800),
    desc = parts[4] or "",
    sunrise = tonumber(parts[5] or 0),
    sunset = tonumber(parts[6] or 0),
    tz_offset = tonumber(parts[7] or 0),
    wind = tonumber(parts[8] or 0),
    humidity = tonumber(parts[9] or 0),
    pressure = tonumber(parts[10] or 0),
    feels = tonumber(parts[11] or 0),
    place = parts[12] or "",
    lat = parts[13],
    lon = parts[14],
    hourly_temps = hourly_temps,
    daily = daily,
    alerts = alerts,
  }
end

local function try_read_location_cache()
  local cached = read_file(location_cache)
  if not cached or cached == "" then return nil end
  local parts = split(trim_newline(cached), "|")
  if #parts < 3 then return nil end
  local ts = tonumber(parts[1] or 0) or 0
  local lat = parts[2]
  local lon = parts[3]
  local label = parts[4] or ""
  if ts <= 0 or not lat or not lon or lat == "" or lon == "" then return nil end
  if os.time() - ts >= LOCATION_TTL then return nil end
  return { ts = ts, lat = lat, lon = lon, label = label }
end

local function write_location_cache(lat, lon, label)
  if not lat or not lon then return end
  lat = tostring(lat)
  lon = tostring(lon)
  label = sanitize_field(label or "")
  local line = string.format("%d|%s|%s|%s\n", os.time(), lat, lon, label)
  write_file(location_cache, line)
end

local function resolve_location(callback)
  local cached = try_read_location_cache()
  if cached then
    callback(cached)
    return
  end

  local app_bundle = os.getenv("HOME") .. "/.config/sketchybar/helpers/location/bin/SketchyBarLocationHelper.app"
  sbar.exec("/bin/zsh -lc 'open -W " .. app_bundle .. " >/dev/null 2>&1'", function()
    local raw = read_file(location_cache)
    raw = trim_newline(raw or "")
    local parts = split(raw, "|")
    if #parts >= 3 then
      callback({
        ts = tonumber(parts[1] or 0) or os.time(),
        lat = parts[2],
        lon = parts[3],
        label = parts[4] or "",
      })
    else
      callback(nil)
    end
  end)
end

local cached_api_key = nil
local api_key_checked = false
local function get_api_key(callback)
  if api_key_checked then
    callback(cached_api_key)
    return
  end
  api_key_checked = true
  local cmd = [[/bin/zsh -lc "security find-generic-password -a "$USER" -s OPENWEATHERMAP_API_KEY -w 2>/dev/null || true"]]
  sbar.exec(cmd, function(out)
    local key = trim_newline(out or "")
    cached_api_key = (key ~= "") and key or nil
    callback(cached_api_key)
  end)
end

-- Widget (compact, battery-style) with cached render state.
local last_widget_icon = nil
local last_widget_color = nil
local last_widget_label = nil

local weather = sbar.add("item", "widgets.weather", {
  position = "right",
  icon = {
    font = { style = settings.font.style_map["Regular"], size = 12.0 },
    padding_right = settings.paddings,
    color = colors.white,
    string = "☁️",
  },
  label = {
    font = { family = settings.font.numbers },
    width = 44,
    padding_left = 2,
    padding_right = 4,
    string = "--°C",
    color = colors.white,
  },
  padding_left = 0,
  padding_right = 0,
  update_freq = WEATHER_TTL,
  background = { drawing = false },
})

-- Popup (battery-style rows).
local popup_width = 420
local weather_popup = center_popup.create("weather.popup", {
  width = popup_width,
  height = 520,
  popup_height = 26,
  title = "Weather " .. icons.refresh,
  meta = "",
  auto_hide = false,
})
weather_popup.meta_item:set({ drawing = false })
weather_popup.body_item:set({ drawing = false })

local popup_pos = weather_popup.position
local name_width = 160
local value_width = popup_width - name_width

local function add_row(key, title)
  return sbar.add("item", "weather.popup." .. key, {
    position = popup_pos,
    width = popup_width,
    icon = {
      align = "left",
      string = title,
      width = name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 12.0 },
    },
    label = {
      align = "right",
      string = "-",
      width = value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 12.0 },
      max_chars = 64,
    },
    background = { drawing = false },
  })
end

local row_updated = add_row("updated", "Updated")
local row_location = add_row("location", "Location")
local row_condition = add_row("condition", "Condition")
local row_temp = add_row("temp", "Temperature")
local row_feels = add_row("feels", "Feels like")

-- Humidity row (after Feels like)
local humidity_bar = sbar.add("item", "weather.popup.humidity_bar", {
  position = popup_pos,
  width = popup_width,
  icon = {
    align = "left",
    string = "Humidity",
    width = name_width,
    font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 12.0 },
  },
  label = {
    align = "right",
    string = "░░░░░░░░░░ 0%",
    width = value_width,
    font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 12.0 },
  },
  background = { drawing = false },
})

local row_wind = add_row("wind", "Wind")
local row_pressure = add_row("pressure", "Pressure")
local row_sunrise = add_row("sunrise", "Sunrise")
local row_sunset = add_row("sunset", "Sunset")
local row_tz = add_row("tz", "Time zone")

local function make_humidity_bar(percent)
  local p = tonumber(percent) or 0
  local filled = math.floor(p / 10 + 0.5)
  local empty = 10 - filled
  return string.rep("█", filled) .. string.rep("░", empty) .. string.format(" %d%%", p)
end

-- 5-day forecast section
weather_popup.add_section("daily", "5-DAY OUTLOOK")

local forecast_rows = {}
for i = 1, 5 do
  forecast_rows[i] = add_row("day" .. i, "Day " .. i)
end

local day_names_zh = {"周日", "周一", "周二", "周三", "周四", "周五", "周六"}

local function make_rain_indicator(pop)
  local p = tonumber(pop) or 0
  if p < 0.1 then return "" end
  local pct = round_int(p * 100)
  -- Use rain drop density to show probability
  if pct >= 80 then return "🌧️" .. pct .. "%" end
  if pct >= 50 then return "🌦️" .. pct .. "%" end
  if pct >= 20 then return "💧" .. pct .. "%" end
  return "💧" .. pct .. "%"
end

local function update_daily_forecast(daily_data)
  if not daily_data then
    for i = 1, 5 do
      if forecast_rows[i] then
        forecast_rows[i]:set({ icon = { string = "-" }, label = { string = "-" } })
      end
    end
    return
  end
  for i, day in ipairs(daily_data) do
    if i > 5 or not forecast_rows[i] then break end
    local date = os.date("*t", day.dt)
    local day_name = day_names_zh[date.wday]
    local weather_icon = owm_icon_for(day.weather_id, true)
    -- Fixed width format: icon + temps, right aligned
    local temp_str = string.format("%3d°/%2d°", round_int(day.temp_max), round_int(day.temp_min))
    forecast_rows[i]:set({
      icon = { string = day_name },
      label = { string = weather_icon .. "   " .. temp_str },
    })
  end
end

-- Weather alert row
local row_alert = sbar.add("item", "weather.popup.alert", {
  position = popup_pos,
  width = popup_width,
  drawing = false,
  icon = {
    align = "left",
    string = "⚠️",
    width = 30,
    color = colors.red,
  },
  label = {
    align = "left",
    string = "",
    width = popup_width - 30,
    font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 11.0 },
    color = colors.red,
    max_chars = 50,
  },
  background = {
    drawing = true,
    color = colors.with_alpha(colors.red, 0.15),
    corner_radius = 4,
  },
})

local function update_alerts(alerts)
  if not alerts or #alerts == 0 then
    row_alert:set({ drawing = false })
    return
  end
  row_alert:set({
    drawing = true,
    label = { string = alerts[1].event or "Weather Alert" },
  })
end

weather_popup.add_close_row({ label = "close x" })

local current_data = nil
local current_error = nil
local current_location_label = nil
local current_location_lat = nil
local current_location_lon = nil

local geocode_in_flight = false
local last_geocode_attempt = 0

local function set_location_state(lat, lon, label)
  lat = lat and tostring(lat) or ""
  lon = lon and tostring(lon) or ""
  if lat == "" or lon == "" then return end

  if current_location_lat ~= lat or current_location_lon ~= lon then
    current_location_lat = lat
    current_location_lon = lon
    current_location_label = nil
  end

  label = tostring(label or "")
  if label ~= "" then
    current_location_label = label
  end
end

local function hydrate_location_label_from_cache(lat, lon)
  lat = lat and tostring(lat) or ""
  lon = lon and tostring(lon) or ""
  if lat == "" or lon == "" then return end

  set_location_state(lat, lon, nil)
  local cached = try_read_location_cache()
  if cached and tostring(cached.lat) == lat and tostring(cached.lon) == lon then
    local label = tostring(cached.label or "")
    if label ~= "" then
      set_location_state(lat, lon, label)
    end
  end
end

local function set_widget(icon, color, label)
  if icon == last_widget_icon and color == last_widget_color and label == last_widget_label then
    return
  end
  last_widget_icon = icon
  last_widget_color = color
  last_widget_label = label
  weather:set({
    icon = { string = icon, color = color },
    label = { string = label },
  })
end

local function set_error(err)
  current_error = err
  set_widget("⚠️", colors.red, "--°C")
end

local function update_popup(force)
  if not force and not weather_popup.is_showing() then return end

  local updated_label = "-"
  if current_error then
    updated_label = tostring(current_error)
  elseif not current_data then
    updated_label = "Loading…"
  else
    local ts = tonumber(current_data.ts) or 0
    if ts > 0 then
      updated_label = os.date("%Y-%m-%d %H:%M", ts)
    end
  end
  row_updated:set({ label = { string = updated_label } })

  local place = nil
  if current_location_label and current_location_label ~= "" then
    place = current_location_label
  elseif current_data and current_data.place and current_data.place ~= "" then
    place = current_data.place
  else
    local lat_s = current_location_lat or (current_data and current_data.lat) or ""
    local lon_s = current_location_lon or (current_data and current_data.lon) or ""
    local latn = tonumber(lat_s)
    local lonn = tonumber(lon_s)
    if latn and lonn then
      place = string.format("%d, %d", math.floor(latn), math.floor(lonn))
    end
  end
  row_location:set({ label = { string = place or "-" } })

  if not current_data then
    row_condition:set({ label = { string = "-" } })
    row_temp:set({ label = { string = "-" } })
    row_feels:set({ label = { string = "-" } })
    humidity_bar:set({ label = { string = "░░░░░░░░░░ 0%" } })
    row_wind:set({ label = { string = "-" } })
    row_pressure:set({ label = { string = "-" } })
    row_sunrise:set({ label = { string = "-" } })
    row_sunset:set({ label = { string = "-" } })
    row_tz:set({ label = { string = "-" } })
    update_daily_forecast(nil)
    update_alerts(nil)
    return
  end

  local condition_label = current_data.desc or ""
  local zh = owm_zh_for(current_data.id)
  if zh and zh ~= "" then
    if condition_label ~= "" then
      condition_label = condition_label .. " " .. zh
    else
      condition_label = zh
    end
  end

  -- Add weather icon to condition
  local now = os.time()
  local is_day = (now >= (current_data.sunrise or 0)) and (now < (current_data.sunset or 0))
  local condition_icon = owm_icon_for(current_data.id, is_day)
  local condition_display = condition_icon .. " " .. (condition_label ~= "" and condition_label or "-")

  row_condition:set({ label = { string = condition_display } })
  row_temp:set({ label = { string = format_temp_c(current_data.temp) } })
  row_feels:set({ label = { string = format_temp_c(current_data.feels) } })
  humidity_bar:set({ label = { string = make_humidity_bar(current_data.humidity) } })
  row_wind:set({ label = { string = format_wind(current_data.wind) } })
  row_pressure:set({ label = { string = format_pressure(current_data.pressure) } })

  row_sunrise:set({ label = { string = format_time_local(current_data.sunrise, current_data.tz_offset) } })
  row_sunset:set({ label = { string = format_time_local(current_data.sunset, current_data.tz_offset) } })

  local off = tonumber(current_data.tz_offset) or 0
  local sign = (off >= 0) and "+" or "-"
  local abs = math.abs(off)
  local hh = math.floor(abs / 3600)
  local mm = math.floor((abs % 3600) / 60)
  row_tz:set({ label = { string = string.format("UTC%s%02d:%02d", sign, hh, mm) } })

  -- Update new components
  update_daily_forecast(current_data.daily)
  update_alerts(current_data.alerts)
end

local function maybe_reverse_geocode(lat, lon, opts)
  opts = opts or {}
  local force = opts.force == true

  if not weather_popup.is_showing() then return end
  lat = lat and tostring(lat) or ""
  lon = lon and tostring(lon) or ""
  if lat == "" or lon == "" then return end

  set_location_state(lat, lon, nil)

  if not force and current_location_label and current_location_label ~= "" then
    return
  end
  if geocode_in_flight then return end

  local now = os.time()
  if now - last_geocode_attempt < 10 then return end
  last_geocode_attempt = now

  geocode_in_flight = true
  reverse_geocode_label(lat, lon, function(label)
    geocode_in_flight = false
    label = tostring(label or "")
    if label == "" then return end
    if current_location_lat ~= lat or current_location_lon ~= lon then return end
    set_location_state(lat, lon, label)
    write_location_cache(lat, lon, label)
    update_popup(true)
  end)
end

local function apply_weather(data)
  current_error = nil
  current_data = data

  if not data then
    set_error("Unavailable")
    update_popup(true)
    return
  end

  local now = os.time()
  local is_day = (now >= (data.sunrise or 0)) and (now < (data.sunset or 0))
  local icon = owm_icon_for(data.id, is_day)
  set_widget(icon, colors.white, format_temp_c(data.temp))
  update_popup(false)
end

local refresh_token = 0
local function refresh(force)
  if _G.SKETCHYBAR_SUSPENDED then return end
  refresh_token = refresh_token + 1
  local token = refresh_token

  if not force then
    local cached = try_read_weather_cache()
    if cached then
      hydrate_location_label_from_cache(cached.lat, cached.lon)
      apply_weather(cached)
      maybe_reverse_geocode(cached.lat, cached.lon, { force = false })
      return
    end
  end

  current_data = nil
  current_error = nil
  update_popup(false)

  get_api_key(function(key)
    if token ~= refresh_token then return end
    if not key then
      set_error("Missing API key")
      update_popup(true)
      return
    end

    resolve_location(function(loc)
      if token ~= refresh_token then return end
      if not loc then
        set_error("Location unavailable")
        update_popup(true)
        return
      end

      set_location_state(loc.lat, loc.lon, loc.label)
      update_popup(true)
      maybe_reverse_geocode(loc.lat, loc.lon, { force = force })

      local url = build_weather_url(loc.lat, loc.lon, key)
      sbar.exec(jxa_fetch_onecall(url), function(out)
        if token ~= refresh_token then return end
        out = trim_newline(out or "")
        local data = parse_weather_psv(out)
        if not data then
          set_error("Fetch failed")
          update_popup(true)
          return
        end
        data.lat = loc.lat
        data.lon = loc.lon
        data.ts = os.time()
        write_weather_cache(data)
        apply_weather(data)
      end)
    end)
  end)
end

-- Click handling (battery-style):
-- - Left click: toggle popup
-- - Right click: open Apple Weather app
local function weather_on_click(env)
  if env.BUTTON == "right" then
    sbar.exec("open -a \"Weather\" >/dev/null 2>&1", function() end)
    return
  end
  if env.BUTTON ~= "left" then return end

  if weather_popup.is_showing() then
    weather_popup.hide()
    return
  end

  weather_popup.show(function()
    update_popup(true)
    refresh(false)
  end)
end

weather:subscribe("mouse.clicked", weather_on_click)

-- Header click = force refresh (ignore TTL).
weather_popup.title_item:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" then return end
  refresh(true)
end)

-- Event-driven + low-frequency fallback.
weather:subscribe({ "forced", "routine", "wifi_change", "system_woke" }, function(_)
  refresh(false)
end)

-- Initial paint.
set_widget("☁️", colors.white, "--°C")
refresh(true)


