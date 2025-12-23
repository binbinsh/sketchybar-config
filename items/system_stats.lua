local colors = require("colors")
local settings = require("settings")

sbar.exec("killall system_stats >/dev/null; " .. os.getenv("CONFIG_DIR") .. "/helpers/system_stats/bin/system_stats system_stats_update 1.0")

local cpu_gpu_width = 44
local mem_width = 28

local function usage_color(value)
  if not value then return colors.blue end
  if value >= 80 then return colors.red end
  if value >= 60 then return colors.orange end
  if value >= 40 then return colors.yellow end
  return colors.blue
end

local function make_graph(name, icon_text, color, width)
  return sbar.add("graph", name, width, {
    position = "right",
    graph = { color = color },
    background = {
      height = 22,
      color = { alpha = 0 },
      border_color = { alpha = 0 },
      drawing = true,
    },
    icon = {
      string = icon_text,
      font = {
        family = settings.font.text,
        style = settings.font.style_map["Bold"],
        size = 9.0,
      },
      padding_right = 4,
    },
    label = {
      string = "--",
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 9.0,
      },
      align = "right",
      padding_right = 0,
      width = 0,
      y_offset = 4,
    },
    padding_right = settings.paddings + 6,
  })
end

local mem = make_graph("widgets.sys.mem", "MEM", colors.green, mem_width)
local gpu = make_graph("widgets.sys.gpu", "GPU", colors.magenta, cpu_gpu_width)
local cpu = make_graph("widgets.sys.cpu", "CPU", colors.blue, cpu_gpu_width)

cpu:subscribe("system_stats_update", function(env)
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

  cpu:set({
    graph = { color = usage_color(cpu_total) },
    label = cpu_label,
  })

  gpu:set({
    graph = { color = usage_color(gpu_util) },
    label = gpu_label,
  })

  local mem_percent = tonumber(env.mem_used_percent)
  if mem_percent and mem_percent >= 0 then
    mem:push({ mem_percent / 100.0 })
    mem:set({
      graph = { color = usage_color(mem_percent) },
      label = string.format("%d%%", mem_percent),
    })
  else
    mem:set({ label = "--" })
  end
end)

sbar.add("bracket", "widgets.sys.bracket", {
  cpu.name,
  gpu.name,
  mem.name,
}, {
  background = {
    color = colors.with_alpha(colors.bg1, 0.2),
    border_color = colors.with_alpha(colors.bg2, 0.2),
    border_width = 2,
  }
})

sbar.add("item", "widgets.sys.padding", {
  position = "right",
  width = settings.group_paddings
})
