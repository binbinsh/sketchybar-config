# system stats

## overview

This module adds CPU/GPU usage graphs with current temperatures shown in the label, plus a memory usage graph. The data is produced by the native helper in `helpers/system_stats`.

## build

```bash
make -C helpers
```

## data sources

- CPU usage: `host_statistics` via `helpers/system_stats/cpu.h`
- Memory usage: `host_statistics64` + `sysctl hw.memsize`
- GPU usage: `IOAccelerator` registry `PerformanceStatistics` (Device/Renderer Utilization)

## temperature values

CPU/GPU temperatures are collected from HID temperature services via `IOHIDEventSystemClient`. The helper:

- averages `PMU tdie*` sensors for CPU temperature
- uses the max of `PMU tdev*` sensors for GPU temperature

If those sensors are not available, the helper reports `-1` and the Lua item renders `--C` next to the usage percentage.

## tuning

- Update interval is controlled in `items/widgets/system_stats.lua` by the `system_stats_update` helper invocation.
- Graph widths are configured in `items/widgets/system_stats.lua` (`cpu_gpu_width`, `mem_width`).
