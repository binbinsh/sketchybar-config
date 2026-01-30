local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

sbar.exec("killall system_stats >/dev/null 2>&1; " .. os.getenv("CONFIG_DIR") .. "/helpers/system_stats/bin/system_stats system_stats_update 2.0")

local cpu_gpu_width = 44
local mem_width = 28
local trailing_gap = 16

local function make_graph(name, icon_text, width, padding_right)
  return sbar.add("graph", name, width, {
    position = "right",
    graph = { color = colors.red },
    icon = {
      string = icon_text,
      color = colors.green,
      font = {
        family = settings.font.text,
        style = settings.font.style_map["Heavy"],
        size = 9.0,
      },
      padding_right = 4,
    },
    label = {
      string = "--",
      color = colors.white,
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 9.0,
      },
      align = "right",
      padding_left = 2,
      padding_right = 6,
      width = 0,
      y_offset = 4,
    },
    padding_left = 0,
    padding_right = padding_right or 0,
  })
end

local mem = make_graph("widgets.sys.mem", "MEM", mem_width, trailing_gap)
local gpu = make_graph("widgets.sys.gpu", "GPU", cpu_gpu_width, 0)
local cpu = make_graph("widgets.sys.cpu", "CPU", cpu_gpu_width, 0)

-- Popup setup
local popup_width = 360
local stats_popup = center_popup.create("system_stats.popup", {
  width = popup_width,
  height = 500,
  popup_height = 26,
  title = "System Stats",
  meta = "",
  auto_hide = false,
})
stats_popup.meta_item:set({ drawing = false })
stats_popup.body_item:set({ drawing = false })

local popup_pos = stats_popup.position
local name_width = 220
local value_width = popup_width - name_width

-- Helper to add info rows
local function add_row(key, title)
  return sbar.add("item", "system_stats.popup." .. key, {
    position = popup_pos,
    width = popup_width,
    icon = {
      align = "left",
      string = title,
      width = name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Regular"], size = 11.0 },
    },
    label = {
      align = "right",
      string = "-",
      width = value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 11.0 },
    },
    background = { drawing = false },
  })
end

-- CPU section
stats_popup.add_section("cpu", "CPU")
local cpu_rows = {}
for i = 1, 10 do
  cpu_rows[i] = add_row("cpu_proc" .. i, "")
end

-- MEM section
stats_popup.add_section("mem", "MEM")
local mem_rows = {}
for i = 1, 10 do
  mem_rows[i] = add_row("mem_proc" .. i, "")
end

stats_popup.add_close_row({ label = "close x" })

-- Fetch and display top processes for both CPU and MEM
local function refresh_popup()
  -- Fetch CPU processes
  sbar.exec("ps -Aceo pcpu,comm -r | head -11 | tail -10", function(output)
    local text = ""
    if type(output) == "string" then
      text = output
    elseif type(output) == "table" then
      text = output[1] or output.stdout or ""
    end
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local idx = 1
    for line in text:gmatch("[^\r\n]+") do
      if idx > 10 then break end
      local val, name = line:match("^%s*([%d%.]+)%s+(.+)$")
      if val and name then
        if #name > 28 then name = name:sub(1, 25) .. "..." end
        cpu_rows[idx]:set({
          icon = { string = name },
          label = { string = val .. "%" },
        })
        idx = idx + 1
      end
    end
    for i = idx, 10 do
      cpu_rows[i]:set({ icon = { string = "" }, label = { string = "" } })
    end
  end)

  -- Fetch MEM processes
  sbar.exec("ps -Aceo rss,comm -m | head -11 | tail -10", function(output)
    local text = ""
    if type(output) == "string" then
      text = output
    elseif type(output) == "table" then
      text = output[1] or output.stdout or ""
    end
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")

    local idx = 1
    for line in text:gmatch("[^\r\n]+") do
      if idx > 10 then break end
      local val, name = line:match("^%s*([%d%.]+)%s+(.+)$")
      if val and name then
        if #name > 28 then name = name:sub(1, 25) .. "..." end
        local kb = tonumber(val) or 0
        local display_val
        if kb >= 1048576 then
          display_val = string.format("%.1f GB", kb / 1048576)
        elseif kb >= 1024 then
          display_val = string.format("%.0f MB", kb / 1024)
        else
          display_val = string.format("%d KB", kb)
        end
        mem_rows[idx]:set({
          icon = { string = name },
          label = { string = display_val },
        })
        idx = idx + 1
      end
    end
    for i = idx, 5 do
      mem_rows[i]:set({ icon = { string = "" }, label = { string = "" } })
    end
  end)
end

-- Click on header title to refresh
stats_popup.title_item:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then
    refresh_popup()
  end
end)

-- Toggle popup
local function toggle_popup()
  if stats_popup.is_showing() then
    stats_popup.hide()
  else
    stats_popup.show(function()
      refresh_popup()
    end)
  end
end

-- All widgets open the same popup
cpu:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then toggle_popup() end
end)

gpu:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then toggle_popup() end
end)

mem:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then toggle_popup() end
end)

cpu:subscribe("system_stats_update", function(env)
  if _G.SKETCHYBAR_SUSPENDED then return end

  local cpu_total = tonumber(env.cpu_total)
  local cpu_temp_val = tonumber(env.cpu_temp)
  local cpu_label = cpu_total and string.format("%d%%", cpu_total) or "--"
  if cpu_total then
    cpu:push({ cpu_total / 100.0 })
  end

  if cpu_temp_val and cpu_temp_val >= 0 then
    cpu_label = string.format("%s %dC", cpu_label, cpu_temp_val)
  else
    cpu_label = string.format("%s --C", cpu_label)
  end

  local gpu_util = tonumber(env.gpu_util)
  local gpu_temp_val = tonumber(env.gpu_temp)
  local gpu_label = gpu_util and string.format("%d%%", gpu_util) or "--"
  if gpu_util and gpu_util >= 0 then
    gpu:push({ gpu_util / 100.0 })
  end

  if gpu_temp_val and gpu_temp_val >= 0 then
    gpu_label = string.format("%s %dC", gpu_label, gpu_temp_val)
  else
    gpu_label = string.format("%s --C", gpu_label)
  end

  cpu:set({ label = cpu_label })
  gpu:set({ label = gpu_label })

  local mem_percent = tonumber(env.mem_used_percent)
  if mem_percent and mem_percent >= 0 then
    mem:push({ mem_percent / 100.0 })
    mem:set({
      label = string.format("%d%%", mem_percent),
    })
  else
    mem:set({ label = "--" })
  end
end)
