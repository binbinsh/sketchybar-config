local colors = require("colors")
local settings = require("settings")
local app_icons = require("app_icons")
local center_popup = require("center_popup")

local cache_dir = os.getenv("HOME") .. "/.cache/sketchybar"
local last_seen_path = cache_dir .. "/github_last_seen.txt"
local orgs_env = os.getenv("GITHUB_ORGS") or ""

-- Ensure cache dir exists
sbar.exec("/bin/zsh -lc 'mkdir -p " .. cache_dir .. "'")

local github = sbar.add("item", "widgets.github", {
  position = "right",
  icon = {
    string = app_icons["GitHub Desktop"] or "GH",
    font = "sketchybar-app-font:Regular:16.0",
    color = colors.white,
  },
  label = {
    drawing = false,
    string = "",
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
    },
    color = colors.white,
  },
  background = { drawing = false },
  padding_left = settings.paddings,
  padding_right = settings.paddings,
  updates = true,
})

local popup_width = 480
local github_popup = center_popup.create("github.popup", {
  width = popup_width,
  height = 300,
  popup_height = 26,
  title = "GitHub",
  meta = "",
})
github_popup.meta_item:set({ drawing = false })
github_popup.body_item:set({ drawing = false })

local popup_pos = github_popup.position

local title_item = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  align = "center",
  icon = {
    string = app_icons["GitHub Desktop"] or "GH",
    font = "sketchybar-app-font:Regular:16.0",
  },
  label = {
    string = "GitHub",
    font = { size = 15, style = settings.font.style_map["Bold"] },
  },
  background = { height = 2, color = colors.grey, y_offset = -15 },
})

local status_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Status:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local auth_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  drawing = false,
  icon = { align = "left", string = "Login:", width = popup_width / 2 },
  label = { align = "right", string = "gh auth login", width = popup_width / 2 },
})

local auth_status_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  drawing = false,
  icon = { align = "left", string = "Check:", width = popup_width / 2 },
  label = { align = "right", string = "gh auth status", width = popup_width / 2 },
})

local gh_install_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  drawing = false,
  icon = { align = "left", string = "Install:", width = popup_width / 2 },
  label = { align = "right", string = "brew install gh", width = popup_width / 2 },
})

local user_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "User:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local repos_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Repos:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local followers_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Followers:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local following_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Following:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local open_issues_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Open issues:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local open_prs_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Open PRs:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local assigned_issues_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Assigned issues:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local review_requests_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Review requests:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local new_issues_row = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "New issues:", width = popup_width / 2 },
  label = { align = "right", string = "-", width = popup_width / 2 },
})

local action_open_issues = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Open issues", width = popup_width },
  label = { drawing = false },
})

local action_open_notifications = sbar.add("item", {
  position = popup_pos,
  width = popup_width,
  icon = { align = "left", string = "Open notifications", width = popup_width },
  label = { drawing = false },
})

local function trim_newline(s)
  return (s or ""):gsub("\r", ""):gsub("\n$", "")
end

local function trim_spaces(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function split(s, sep)
  local parts = {}
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

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function load_last_seen()
  local raw = trim_spaces(read_file(last_seen_path) or "")
  if raw ~= "" then return raw end
  local stamp = now_iso()
  write_file(last_seen_path, stamp)
  return stamp
end

local function mark_seen()
  write_file(last_seen_path, now_iso())
end

local function github_fetch_cmd(since, orgs)
  local env_parts = {}
  if since and since ~= "" then
    env_parts[#env_parts + 1] = "export GITHUB_SINCE=" .. string.format("%q", since)
  end
  if orgs and orgs ~= "" then
    env_parts[#env_parts + 1] = "export GITHUB_ORGS=" .. string.format("%q", orgs)
  end
  local env_prefix = table.concat(env_parts, "; ")
  if env_prefix ~= "" then env_prefix = env_prefix .. "; " end

  local script = [=[
if ! command -v gh >/dev/null 2>&1; then
  echo "ERR|gh_missing"
  exit 0
fi

user_info=$(gh api /user --jq '[.login, (.name // ""), (.public_repos + .total_private_repos), .followers, .following] | @tsv' 2>/dev/null) || {
  echo "ERR|auth_failed"
  exit 0
}

IFS=$'\t' read -r login name repos followers following <<< "$user_info"
if [ -z "$login" ]; then
  echo "ERR|auth_failed"
  exit 0
fi

scopes=()
scopes+=("user:$login")
if [ -n "$GITHUB_ORGS" ]; then
  IFS=',' read -rA orgs <<< "$GITHUB_ORGS"
  for org in "${orgs[@]}"; do
    org="${org#"${org%%[![:space:]]*}"}"
    org="${org%"${org##*[![:space:]]}"}"
    if [ -n "$org" ]; then
      scopes+=("org:$org")
    fi
  done
fi

search_total() {
  local base="$1"
  local total=0
  local scope q count
  for scope in "${scopes[@]}"; do
    q="$base"
    if [ -n "$scope" ]; then
      q="$q $scope"
    fi
    count=$(gh api graphql \
      -f query='query($q:String!){search(query:$q,type:ISSUE){issueCount}}' \
      -f q="$q" \
      --jq '.data.search.issueCount' 2>/dev/null) || return 1
    total=$((total + count))
  done
  echo "$total"
}

open_issues=$(search_total "is:issue is:open") || { echo "ERR|search_failed"; exit 0; }
open_prs=$(search_total "is:pr is:open") || { echo "ERR|search_failed"; exit 0; }
if [ -n "$GITHUB_SINCE" ]; then
  new_issues=$(search_total "is:issue is:open created:>$GITHUB_SINCE") || { echo "ERR|search_failed"; exit 0; }
else
  new_issues=0
fi
assigned_issues=$(search_total "is:issue is:open assignee:$login") || { echo "ERR|search_failed"; exit 0; }
review_requests=$(search_total "is:pr is:open review-requested:$login") || { echo "ERR|search_failed"; exit 0; }

echo "OK|$login|$name|$repos|$followers|$following|$open_issues|$open_prs|$assigned_issues|$review_requests|$new_issues"
]=]
  local script_path = cache_dir .. "/github_fetch.zsh"
  write_file(script_path, script)

  local cmd = env_prefix .. "/bin/zsh " .. string.format("%q", script_path)
  return "/bin/zsh -lc " .. string.format("%q", cmd)
end

local state = {
  badge_count = 0,
  badge_error = false,
  login = "",
}

local function badge_label(count)
  if count > 99 then return "99+" end
  return tostring(count)
end

local function apply_badge()
  if state.badge_error then
    github:set({ label = { drawing = true, string = "!" }, icon = { color = colors.red } })
    return
  end
  if state.badge_count > 0 then
    github:set({
      label = { drawing = true, string = badge_label(state.badge_count) },
      icon = { color = colors.green },
    })
  else
    github:set({ label = { drawing = false, string = "" }, icon = { color = colors.white } })
  end
end

local function clear_new_issues()
  mark_seen()
  state.badge_count = 0
  new_issues_row:set({ label = { string = "0" } })
  apply_badge()
end

local function set_status(message)
  status_row:set({ label = { string = message } })
end

local function set_auth_hint(show)
  auth_row:set({ drawing = show })
end

local function set_auth_status_hint(show)
  auth_status_row:set({ drawing = show })
end

local function set_gh_install_hint(show)
  gh_install_row:set({ drawing = show })
end

local function reset_rows()
  user_row:set({ label = { string = "-" } })
  repos_row:set({ label = { string = "-" } })
  followers_row:set({ label = { string = "-" } })
  following_row:set({ label = { string = "-" } })
  open_issues_row:set({ label = { string = "-" } })
  open_prs_row:set({ label = { string = "-" } })
  assigned_issues_row:set({ label = { string = "-" } })
  review_requests_row:set({ label = { string = "-" } })
  new_issues_row:set({ label = { string = "-" } })
end

local function update_rows(data)
  user_row:set({ label = { string = data.user } })
  repos_row:set({ label = { string = data.repos } })
  followers_row:set({ label = { string = data.followers } })
  following_row:set({ label = { string = data.following } })
  open_issues_row:set({ label = { string = data.open_issues } })
  open_prs_row:set({ label = { string = data.open_prs } })
  assigned_issues_row:set({ label = { string = data.assigned_issues } })
  review_requests_row:set({ label = { string = data.review_requests } })
  new_issues_row:set({ label = { string = data.new_issues } })
end

local function update_github()
  local since = load_last_seen()
  local cmd = github_fetch_cmd(since, orgs_env)
  sbar.exec(cmd, function(out)
    local raw = trim_newline(out or "")
    if raw == "" then return end
    local parts = split(raw, "|")
    if parts[1] ~= "OK" then
      state.badge_error = true
      reset_rows()
      local err = parts[2] or "Error"
      if err == "gh_missing" then
        set_status("gh missing")
        set_auth_hint(false)
        set_auth_status_hint(false)
        set_gh_install_hint(true)
      elseif err == "auth_failed" then
        set_status("gh auth required")
        set_auth_hint(true)
        set_auth_status_hint(true)
        set_gh_install_hint(false)
      elseif err == "search_failed" then
        set_status("search failed")
        set_auth_hint(false)
        set_auth_status_hint(false)
        set_gh_install_hint(false)
      else
        set_status(err)
        set_auth_hint(false)
        set_auth_status_hint(false)
        set_gh_install_hint(false)
      end
      apply_badge()
      return
    end

    state.badge_error = false
    state.login = parts[2] or ""
    set_auth_hint(false)
    set_auth_status_hint(false)
    set_gh_install_hint(false)

    local repos = parts[4] or "0"
    local followers = parts[5] or "0"
    local following = parts[6] or "0"
    local open_issues = parts[7] or "0"
    local open_prs = parts[8] or "0"
    local assigned_issues = parts[9] or "0"
    local review_requests = parts[10] or "0"
    local new_issues = parts[11] or "0"

    local user_label = state.login
    if user_label == "" then user_label = "-" end

    set_status("OK")
    update_rows({
      user = user_label,
      repos = repos,
      followers = followers,
      following = following,
      open_issues = open_issues,
      open_prs = open_prs,
      assigned_issues = assigned_issues,
      review_requests = review_requests,
      new_issues = new_issues,
    })

    state.badge_count = tonumber(new_issues) or 0
    apply_badge()
  end)
end

github:subscribe("mouse.entered", function(_)
  github:set({ icon = { color = colors.blue } })
end)

github:subscribe("mouse.exited", function(_)
  apply_badge()
end)

github:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" then return end
  if github_popup.is_showing() then
    github_popup.hide()
  else
    github_popup.show(update_github)
  end
end)

action_open_issues:subscribe("mouse.clicked", function(_)
  clear_new_issues()
  sbar.exec("/bin/zsh -lc 'open https://github.com/issues'")
end)

action_open_notifications:subscribe("mouse.clicked", function(_)
  sbar.exec("/bin/zsh -lc 'open https://github.com/notifications'")
end)

github_popup.add_close_row()

github:set({ update_freq = 120 })
github:subscribe("routine", function(_) update_github() end)
github:subscribe({ "front_app_switched", "system_woke" }, function(_) update_github() end)

update_github()
