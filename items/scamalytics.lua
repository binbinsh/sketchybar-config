local M = {}

local DEFAULT_HOST = "https://api11.scamalytics.com/v3/"
local DEFAULT_PUBLIC_IP_URL = "https://api64.ipify.org"
local DEFAULT_KEYCHAIN_SERVICE = "SCAMALYTICS_API_KEY"
local DEFAULT_USER_SERVICE = "SCAMALYTICS_API_USER"
local SCORE_TOTAL = 100

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function is_premium_field(value)
  if value == nil then return false end
  local str = tostring(value)
  return str:lower():find("premium field", 1, true) ~= nil
end

local function normalize_host(host)
  host = trim(host)
  if host == "" then host = DEFAULT_HOST end
  if host:sub(-1) ~= "/" then host = host .. "/" end
  return host
end

local function normalize_user(user)
  user = trim(user)
  user = user:gsub("^/+", ""):gsub("/+$", "")
  return user
end

local function is_valid_ip(value)
  local ip = trim(value)
  if ip == "" then return false end
  if ip:match("^%d+%.%d+%.%d+%.%d+$") then return true end
  if ip:find(":") then return true end
  return false
end

local function pick_first(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if value ~= nil then
      value = tostring(value)
      if value ~= "" then return value end
    end
  end
  return nil
end

local function format_number(value)
  local num = tonumber(value)
  if not num then return nil end
  if num == math.floor(num) then
    return tostring(math.floor(num))
  end
  return string.format("%g", num)
end

local function format_score(score, total)
  local score_str = format_number(score)
  if not score_str then return nil end
  local total_str = format_number(total)
  if total_str then
    return score_str .. " / " .. total_str
  end
  return score_str
end

local function format_country(country, code)
  local name = pick_first(country)
  local short = pick_first(code)
  if name and short and not name:find(short, 1, true) then
    return name .. " (" .. short .. ")"
  end
  return name or short
end

local function format_city(city, state)
  local name = pick_first(city)
  local region = pick_first(state)
  if name and region then
    if name:find(region, 1, true) then return name end
    return name .. ", " .. region
  end
  return name
end

local function format_asn(asn, name)
  local number = pick_first(asn)
  local label = pick_first(name)
  if number and label then
    return number .. " (" .. label .. ")"
  end
  return number or label
end

local function pick_asn(sources)
  for _, source in ipairs(sources or {}) do
    if type(source) == "table" then
      local value = format_asn(source.asn, source.as_name)
      if value then return value end
    end
  end
  return nil
end

local function collect_true_flags(entries)
  local out = {}
  local seen = {}
  for _, entry in ipairs(entries or {}) do
    if entry.value == true then
      local label = tostring(entry.label or "")
      if label ~= "" and not seen[label] then
        out[#out + 1] = label
        seen[label] = true
      end
    end
  end
  if #out == 0 then return nil end
  return table.concat(out, ", ")
end

local function new_client(opts)
  opts = opts or {}
  local host = normalize_host(opts.host)
  local user = normalize_user(opts.user or "")
  local keychain_service = trim(opts.keychain_service or DEFAULT_KEYCHAIN_SERVICE)
  local user_service = trim(opts.user_service or DEFAULT_USER_SERVICE)
  local public_ip_url = trim(opts.public_ip_url or DEFAULT_PUBLIC_IP_URL)
  local cache_ttl = tonumber(opts.cache_ttl) or 900

  local user_checked = false
  local user_cached = nil
  local key_checked = false
  local key_cached = nil
  local cache = nil
  local cache_ip = nil
  local cache_ts = 0
  local inflight = false
  local inflight_token = 0
  local inflight_started_at = 0

  local function get_user(callback)
    if user ~= "" then
      callback(user)
      return
    end
    if user_checked then
      callback(user_cached)
      return
    end
    user_checked = true
    local cmd = string.format(
      "/bin/zsh -lc 'security find-generic-password -a \"$(/usr/bin/id -un)\" -s %q -w 2>/dev/null || true'",
      user_service
    )
    sbar.exec(cmd, function(out)
      local out_user = normalize_user(out)
      user_cached = (out_user ~= "") and out_user or nil
      callback(user_cached)
    end)
  end

  local function get_key(callback)
    if key_checked then
      callback(key_cached)
      return
    end
    key_checked = true
    local cmd = string.format(
      "/bin/zsh -lc 'security find-generic-password -a \"$(/usr/bin/id -un)\" -s %q -w 2>/dev/null || true'",
      keychain_service
    )
    sbar.exec(cmd, function(out)
      local key = trim(out)
      key_cached = (key ~= "") and key or nil
      callback(key_cached)
    end)
  end

  local function fetch_public_ip(callback)
    local cmd = string.format("/bin/zsh -lc '/usr/bin/curl -s --max-time 3 %q'", public_ip_url)
    sbar.exec(cmd, function(out)
      local ip = trim(out)
      if not is_valid_ip(ip) then
        callback(nil)
        return
      end
      callback(ip)
    end)
  end

  local function should_refresh(ip)
    if not cache or not cache_ip then return true end
    if cache_ip ~= ip then return true end
    if (os.time() - cache_ts) >= cache_ttl then return true end
    return false
  end

  local function update(params)
    params = params or {}
    if inflight and (os.time() - inflight_started_at) <= 10 then return end
    inflight = false
    local force = params.force == true
    if not force and params.is_showing and not params.is_showing() then return end
    inflight = true
    inflight_started_at = os.time()
    inflight_token = inflight_token + 1
    local token = inflight_token
    if params.on_stage then params.on_stage("start") end
    sbar.delay(6, function()
      if inflight and token == inflight_token then
        inflight = false
        if params.on_unavailable then params.on_unavailable("timeout") end
      end
    end)
    get_user(function(user_value)
      if params.on_stage then params.on_stage("user") end
      if not user_value then
        inflight = false
        if params.on_unavailable then params.on_unavailable("missing_user") end
        return
      end

      get_key(function(key)
        if params.on_stage then params.on_stage("key") end
        if not key then
          inflight = false
          if params.on_unavailable then params.on_unavailable("missing_key") end
          return
        end

        fetch_public_ip(function(ip)
          if params.on_stage then params.on_stage("public_ip") end
          if not ip then
            inflight = false
            if params.on_unavailable then params.on_unavailable("missing_public_ip") end
            return
          end

          if not force and not should_refresh(ip) then
            inflight = false
            if params.on_result then params.on_result(cache, ip) end
            return
          end

          local endpoint = host .. user_value .. "/"
          if params.on_stage then params.on_stage("request") end
          local cmd = string.format(
            "/bin/zsh -lc '/usr/bin/curl -s -L --max-time 5 --get --data-urlencode %q --data-urlencode %q %q'",
            "key=" .. key,
            "ip=" .. ip,
            endpoint
          )
          sbar.exec(cmd, function(result)
            if params.on_stage then params.on_stage("response") end
            inflight = false
            if type(result) == "table" then
              cache = result
              cache_ip = ip
              cache_ts = os.time()
            end
            if params.on_result then params.on_result(result, ip) end
          end)
        end)
      end)
    end)
  end

  return {
    update = update,
  }
end

local function set_opt_row(row, value)
  if not row then return end
  if value and value ~= "" and not is_premium_field(value) then
    row:set({ drawing = true, label = { string = tostring(value) } })
  else
    row:set({ drawing = false })
  end
end

local function set_section_visible(row, visible)
  if not row then return end
  row:set({ drawing = visible and true or false })
end

function M.attach_popup(opts)
  opts = opts or {}
  local add_row = opts.add_row
  local add_section = opts.add_section
  if type(add_row) ~= "function" or type(add_section) ~= "function" then
    return { update = function() end }
  end

  local rows = {
    title = add_section("scamalytics", "SCAMALYTICS"),
    public_ip = add_row("public_ip", "Public IP", { drawing = false }),
    risk = add_row("scamalytics_risk", "Risk", { drawing = false }),
    score = add_row("scamalytics_score", "Score", { drawing = false }),
    isp = add_row("scamalytics_isp", "ISP", { drawing = false }),
    org = add_row("scamalytics_org", "Organization", { drawing = false }),
    isp_score = add_row("scamalytics_isp_score", "ISP Score", { drawing = false }),
    isp_risk = add_row("scamalytics_isp_risk", "ISP Risk", { drawing = false }),
    country = add_row("scamalytics_country", "Country", { drawing = false }),
    city = add_row("scamalytics_city", "City", { drawing = false }),
    asn = add_row("scamalytics_asn", "ASN", { drawing = false }),
    proxy_type = add_row("scamalytics_proxy_type", "Proxy Type", { drawing = false }),
    flags = add_row("scamalytics_flags", "Flags", { drawing = false }),
    blacklist = add_row("scamalytics_blacklist", "Blacklisted", { drawing = false }),
    url = add_row("scamalytics_url", "Report URL", { drawing = false }),
  }
  rows.title:set({ icon = { align = "center", string = "SCAMALYTICS" } })

  local client = new_client({
    host = opts.host,
    user = opts.user,
    keychain_service = opts.keychain_service,
    user_service = opts.user_service,
    public_ip_url = opts.public_ip_url,
    cache_ttl = opts.cache_ttl,
  })
  local is_showing = opts.is_showing

  local function clear_rows()
    local row_list = {
      rows.public_ip,
      rows.risk,
      rows.score,
      rows.isp,
      rows.org,
      rows.isp_score,
      rows.isp_risk,
      rows.country,
      rows.city,
      rows.asn,
      rows.proxy_type,
      rows.flags,
      rows.blacklist,
      rows.url,
    }
    for _, row in ipairs(row_list) do
      set_opt_row(row, nil)
    end
    set_section_visible(rows.title, false)
  end

  local function report_unavailable(reason)
    clear_rows()
  end

  local function apply_result(result, fallback_ip)
    if type(result) ~= "table" then
      report_unavailable("invalid_response")
      return
    end
    local scam = result.scamalytics
    if type(scam) ~= "table" or scam.status ~= "ok" then
      report_unavailable(scam and scam.status or "bad_status")
      return
    end

    local external = result.external_datasources or {}
    local dbip = external.dbip or {}
    local maxmind = external.maxmind_geolite2 or {}
    local ipinfo = external.ipinfo or {}
    local ip2proxy = external.ip2proxy or {}
    local ip2proxy_lite = external.ip2proxy_lite or {}
    local firehol = external.firehol or {}
    local x4bnet = external.x4bnet or {}
    local google = external.google or {}
    local proxy = scam.scamalytics_proxy or {}
    set_section_visible(rows.title, true)
    set_opt_row(rows.public_ip, pick_first(scam.ip, fallback_ip))
    set_opt_row(rows.risk, scam.scamalytics_risk)
    set_opt_row(rows.score, format_score(scam.scamalytics_score, SCORE_TOTAL))
    set_opt_row(rows.isp, scam.scamalytics_isp)
    set_opt_row(rows.org, scam.scamalytics_org)
    set_opt_row(rows.isp_score, format_score(scam.scamalytics_isp_score, SCORE_TOTAL))
    set_opt_row(rows.isp_risk, scam.scamalytics_isp_risk)
    set_opt_row(rows.country, format_country(
      pick_first(dbip.ip_country_name, maxmind.ip_country_name, ipinfo.ip_country_name, ip2proxy_lite.ip_country_name),
      pick_first(dbip.ip_country_code, maxmind.ip_country_code, ipinfo.ip_country_code, ip2proxy_lite.ip_country_code)
    ))
    set_opt_row(rows.city, format_city(
      pick_first(dbip.ip_city, maxmind.ip_city, ip2proxy_lite.ip_city),
      pick_first(dbip.ip_state_name, maxmind.ip_state_name, dbip.ip_district_name, ip2proxy_lite.ip_district_name)
    ))
    set_opt_row(rows.asn, pick_asn({ ipinfo, maxmind, ip2proxy_lite }))
    set_opt_row(rows.proxy_type, pick_first(ip2proxy.proxy_type, ip2proxy_lite.proxy_type))
    set_opt_row(rows.flags, collect_true_flags({
      { label = "Datacenter", value = proxy.is_datacenter },
      { label = "VPN", value = proxy.is_vpn },
      { label = "iCloud Private Relay", value = proxy.is_apple_icloud_private_relay },
      { label = "AWS", value = proxy.is_amazon_aws },
      { label = "Google", value = proxy.is_google },
      { label = "Proxy", value = firehol.is_proxy },
      { label = "Datacenter", value = x4bnet.is_datacenter },
      { label = "VPN", value = x4bnet.is_vpn },
      { label = "Tor", value = x4bnet.is_tor },
      { label = "Spambot", value = x4bnet.is_blacklisted_spambot },
      { label = "Opera Mini Bot", value = x4bnet.is_bot_operamini },
      { label = "Semrush Bot", value = x4bnet.is_bot_semrush },
      { label = "Google", value = google.is_google_general },
      { label = "Googlebot", value = google.is_googlebot },
      { label = "Special Crawler", value = google.is_special_crawler },
      { label = "User Triggered Fetcher", value = google.is_user_triggered_fetcher },
    }))
    set_opt_row(rows.blacklist, scam.is_blacklisted_external and "Yes" or nil)
    set_opt_row(rows.url, scam.scamalytics_url)
  end

  local function update(force)
    if type(client) ~= "table" or type(client.update) ~= "function" then
      report_unavailable("client_missing")
      return
    end
    local ok, err = pcall(function()
      client.update({
        force = force,
        is_showing = is_showing,
        on_result = apply_result,
        on_unavailable = report_unavailable,
      })
    end)
    if not ok then
      report_unavailable("error:" .. tostring(err))
    end
  end

  return {
    update = update,
    clear = clear_rows,
  }
end

return M
