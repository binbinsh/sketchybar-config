local colors = require("colors")
local settings = require("settings")

sbar.exec("killall system_stats >/dev/null 2>&1; " .. os.getenv("CONFIG_DIR") .. "/helpers/system_stats/bin/system_stats system_stats_update 2.0")

local cpu_gpu_width = 44
local mem_width = 28
local trailing_gap = 16 -- Match the visual gap of other compact widgets (e.g. battery ↔ volume)

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
    -- Battery-style compact spacing (no bracket/padding items).
    padding_left = 0,
    padding_right = padding_right or 0,
  })
end

-- Add a small trailing gap so `system_stats` doesn't visually stick to `weather`.
local mem = make_graph("widgets.sys.mem", "MEM", mem_width, trailing_gap)
local gpu = make_graph("widgets.sys.gpu", "GPU", cpu_gpu_width, 0)
local cpu = make_graph("widgets.sys.cpu", "CPU", cpu_gpu_width, 0)

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
