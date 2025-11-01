local colors = require("colors")
local settings = require("settings")
local icons = require("icons")
local popup = require("helpers.popup")

-- Read SSH target from private file; hide widget when absent/empty
local target_path = os.getenv("HOME") .. "/.config/sketchybar/ubuntu_target"
local f = io.open(target_path, "r")
if not f then return end
local ssh_target = (f:read("*l") or ""):gsub("%s+$", "")
f:close()
if ssh_target == "" then return end

-- Parse helpers
local function trim(s)
  if not s then return "" end
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function short_host(user_at_host)
  local host = user_at_host:match("@([^@]+)$") or user_at_host
  return trim(host:match("^[^.]+") or host)
end

local function shorten_gpu_name(name)
  if not name or name == "" then return "GPU" end
  name = name
    :gsub("^NVIDIA%s+GeForce%s+RTX%s+", "")
    :gsub("^NVIDIA%s+GeForce%s+", "")
    :gsub("^NVIDIA%s+", "")
    :gsub("^GeForce%s+", "")
    :gsub("%s+Graphics$", "")
  local tail = name:match("(%d+%s*[A-Za-z]?)%s*$")
  if tail then name = tail end
  name = name:gsub("(%d+)%s*([A-Za-z])$", "%1%2") -- e.g., 5090 D -> 5090D
  return name
end

local popup_width = 250
local left_col_w = math.floor(popup_width * 0.55)
local right_col_w = popup_width - left_col_w

-- Top-level bar item (icon only)
local ubuntu = sbar.add("item", "widgets.ubuntu", {
  position = "right",
  icon = {
    string = icons.ubuntu or icons.linux,
    color = colors.white,
    font = {
      family = settings.font.text,
      style = settings.font.style_map["Regular"],
      size = 16.0,
    },
  },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = settings.paddings,
  padding_right = settings.paddings,
  updates = true,
  update_freq = 60,
})

local bracket = sbar.add("bracket", "widgets.ubuntu.bracket", { ubuntu.name }, {
  background = { drawing = false },
  popup = { align = "center" },
})

popup.register(bracket)

-- Popup items
local title_item = sbar.add("item", {
  position = "popup." .. bracket.name,
  width = popup_width,
  align = "center",
  icon = { string = icons.ubuntu or icons.linux, color = colors.white, font = { style = settings.font.style_map["Bold"] } },
  label = { string = short_host(ssh_target) .. " " .. icons.refresh, font = { size = 15, style = settings.font.style_map["Bold"] } },
  background = { height = 2, color = colors.grey, y_offset = -15 },
})

-- Load line first
local load_item = sbar.add("item", {
  position = "popup." .. bracket.name,
  icon = { align = "left", string = "Load:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

-- CPU line: usage %, temp °C
local cpu_item = sbar.add("item", {
  position = "popup." .. bracket.name,
  icon = { align = "left", string = "CPU:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

-- Memory line: used/total MiB
local mem_item = sbar.add("item", {
  position = "popup." .. bracket.name,
  icon = { align = "left", string = "Memory:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

-- /home usage line
local home_item = sbar.add("item", {
  position = "popup." .. bracket.name,
  icon = { align = "left", string = "/home:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

-- NVMe temp line
local nvme_item = sbar.add("item", {
  position = "popup." .. bracket.name,
  icon = { align = "left", string = "NVMe:", width = left_col_w },
  label = { align = "right", string = "—", width = right_col_w },
})

-- We'll reuse a fixed pool of rows for GPUs (up to 6)
local gpu_rows = {}
for i = 1, 6 do
  gpu_rows[i] = sbar.add("item", {
    position = "popup." .. bracket.name,
    icon = { align = "left", string = "", width = left_col_w },
    label = { align = "right", string = "", width = right_col_w },
    drawing = false,
  })
end

-- Parsing of the SSH command output
local function parse_ssh_output(out)
  local lines = {}
  for line in tostring(out or ""):gmatch("[^\n]+") do lines[#lines+1] = line end

  local gpus = {}
  local loads = nil -- "0.15, 0.04, 0.09"
  local cpu_use = nil
  local mem_used, mem_total = nil, nil -- from MiB Mem : line
  local tctl = nil
  local nvmes = {}
  local home_total_raw, home_used_raw = nil, nil
  local current_nvme_id = nil

  for _, line in ipairs(lines) do
    -- GPU combined CSV: name, util, temp, mem_used, mem_total (nounits)
    local name, util, temp, memu, memt = line:match("^(.-),%s*([%d%.]+),%s*([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)%s*$")
    if name and util and temp and memu and memt then
      gpus[#gpus+1] = {
        name = trim(name),
        util = tonumber(util),
        temp = tonumber(temp),
        mem_used_mib = tonumber(memu),
        mem_total_mib = tonumber(memt),
      }
    else
      -- NVMe sensors capture (track id and composite temp)
      local nvme_id = line:match("^nvme%-pci%-(%d+)")
      if nvme_id then
        current_nvme_id = tonumber(nvme_id)
      else
        local nv_t = line:match("^Composite:%s*%+([%d%.]+)°C")
        if nv_t and current_nvme_id then
          nvmes[#nvmes+1] = { id = current_nvme_id, temp = tonumber(nv_t) }
          current_nvme_id = nil
        end
      end

      if not loads then
        local l1, l5, l15 = line:match("load average:%s*([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)")
        if l1 and l5 and l15 then
          loads = string.format("%s / %s / %s", l1, l5, l15)
        end
      end
      if not cpu_use then
        local idle = line:match("([%d%.]+)%s*id")
        if idle then
          local idle_n = tonumber(idle) or 0
          local use = 100 - idle_n
          if use < 0 then use = 0 end
          if use > 100 then use = 100 end
          cpu_use = string.format("%.1f%%", use)
        end
      end
      if not mem_used then
        local total, free, used, cache = line:match("MiB Mem%s*:%s*([%d%.]+)%s*total,%s*([%d%.]+)%s*free,%s*([%d%.]+)%s*used,%s*([%d%.]+)%s*buff/cache")
        if total and used then
          mem_total = tonumber(total)
          mem_used = tonumber(used)
        end
      end
      if not tctl then
        local t = line:match("Tctl:%s*%+([%d%.]+)°C")
        if t then tctl = tonumber(t) end
      end
      if (not home_total_raw) or (not home_used_raw) then
        -- Parse: Filesystem Size Used Avail Use% Mounted on
        -- Example: /dev/nvme0n1     13T  141G   13T    2% /home
        local size, used, mount = line:match("^%S+%s+(%S+)%s+(%S+)%s+%S+%s+%S+%s+(%S+)%s*$")
        if size and used and mount == "/home" then
          home_total_raw = size
          home_used_raw = used
        end
      end
    end
  end

  return {
    gpus = gpus,
    loads = loads,
    cpu_use = cpu_use,
    mem_used = mem_used,
    mem_total = mem_total,
    tctl = tctl,
    nvmes = nvmes,
    home_total_raw = home_total_raw,
    home_used_raw = home_used_raw,
  }
end

local function apply_state(st)
  -- GPUs (bottom section); left shows name:, right shows metrics; only used VRAM (GB)
  for i = 1, #gpu_rows do
    local row = gpu_rows[i]
    if i <= #st.gpus then
      local g = st.gpus[i]
      local name = shorten_gpu_name(g.name)
      if g.name and g.name ~= "" then
        row:set({
          icon = { string = name .. ":" },
          label = (function()
            local used_gb = (g.mem_used_mib or 0)/1024
            return string.format("%d%%, %d°C, %.1f GB", math.floor(g.util or 0), math.floor(g.temp or 0), used_gb)
          end)(),
          drawing = true,
        })
      else
        row:set({
          icon = { string = "GPU:" },
          label = (function()
            local used_gb = (g.mem_used_mib or 0)/1024
            return string.format("%d%%, %d°C, %.1f GB", math.floor(g.util or 0), math.floor(g.temp or 0), used_gb)
          end)(),
          drawing = true,
        })
      end
    else
      row:set({ icon = { string = "" }, label = "", drawing = false })
    end
  end

  -- CPU line
  if st.cpu_use or st.tctl then
    local cpu_bits = {}
    if st.cpu_use then cpu_bits[#cpu_bits+1] = st.cpu_use end
    if st.tctl then cpu_bits[#cpu_bits+1] = string.format("%d°C", math.floor(st.tctl)) end
    cpu_item:set({ label = table.concat(cpu_bits, ", ") })
  else
    cpu_item:set({ label = "—" })
  end

  -- Memory line (GB, 1 decimal, spaces around slash)
  if st.mem_used and st.mem_total then
    local used_gb = (st.mem_used or 0)/1024
    local total_gb = (st.mem_total or 0)/1024
    mem_item:set({ label = string.format("%.1f / %.1f GB", used_gb, total_gb) })
  else
    mem_item:set({ label = "—" })
  end

  -- Separate load line
  local load_s = st.loads or "—"
  load_item:set({ label = load_s })

  -- /home usage: use raw human units from df (e.g., 141G / 13T)
  if st.home_total_raw and st.home_used_raw then
    home_item:set({ label = string.format("%s / %s", st.home_used_raw, st.home_total_raw) })
  else
    home_item:set({ label = "—" })
  end

  -- NVMe line: show all temps, compact (e.g., 30/31/28°C)
  if st.nvmes and #st.nvmes > 0 then
    table.sort(st.nvmes, function(a, b) return (a.id or 0) < (b.id or 0) end)
    local temps = {}
    for _, entry in ipairs(st.nvmes) do
      temps[#temps+1] = tostring(math.floor(entry.temp or 0))
    end
    nvme_item:set({ label = table.concat(temps, "·") .. "°C" })
  else
    nvme_item:set({ label = "—" })
  end

end

-- Command: use nounits CSV for GPU (name, util, temp, mem used/total), then free/top/sensors
local remote_cmd = [[nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits && top -bn1 | head -5 && sensors && df -h /home | tail -1]]

local function sh_quote_single(s)
  return "'" .. tostring(s):gsub("'", "'\"'\"'") .. "'"
end

local function build_ssh()
  local ssh_inner = "ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=accept-new " .. ssh_target .. " " .. sh_quote_single(remote_cmd)
  local cmd = "/bin/zsh -lc " .. sh_quote_single(ssh_inner)
  return cmd
end

local function refresh()
  sbar.exec(build_ssh(), function(out, _)
    if not out or out == "" then
      ubuntu:set({ icon = { color = colors.red } })
      return
    end
    local st = parse_ssh_output(out)
    apply_state(st)
  end)
end

ubuntu:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "right" then
    refresh()
    return
  end
  popup.toggle(bracket, function() end)
end)

-- Hover color change for the bar icon
ubuntu:subscribe("mouse.entered", function(_)
  ubuntu:set({ icon = { color = colors.blue } })
end)

ubuntu:subscribe("mouse.exited", function(_)
  ubuntu:set({ icon = { color = colors.white } })
end)

title_item:subscribe("mouse.clicked", function(_)
  refresh()
end)

popup.auto_hide(bracket, ubuntu)

ubuntu:subscribe("routine", function(_) refresh() end)

-- Initial paint
refresh()


