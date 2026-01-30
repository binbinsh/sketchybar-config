#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <mach/mach.h>
#include <mach/task_info.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <libproc.h>

#include "cpu.h"
#include "../sketchybar.h"

#define MAX_TOP_PROCS 10

typedef struct {
  pid_t pid;
  char name[256];
  uint64_t gpu_time;
} proc_gpu_info_t;

// Comparison function for sorting by GPU time (descending)
static int compare_gpu_time(const void *a, const void *b) {
  const proc_gpu_info_t *pa = (const proc_gpu_info_t *)a;
  const proc_gpu_info_t *pb = (const proc_gpu_info_t *)b;
  if (pb->gpu_time > pa->gpu_time) return 1;
  if (pb->gpu_time < pa->gpu_time) return -1;
  return 0;
}

// Get GPU utilization for a single process using task_info
static uint64_t get_process_gpu_time(pid_t pid) {
  mach_port_t task;
  kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
  if (kr != KERN_SUCCESS) return 0;

  struct task_power_info_v2 power_info;
  mach_msg_type_number_t count = TASK_POWER_INFO_V2_COUNT;
  kr = task_info(task, TASK_POWER_INFO_V2, (task_info_t)&power_info, &count);
  mach_port_deallocate(mach_task_self(), task);

  if (kr != KERN_SUCCESS) return 0;
  return power_info.gpu_energy.task_gpu_utilisation;
}

// Get top GPU-using processes and format as string for sketchybar
static void get_top_gpu_processes(char *buffer, size_t bufsize) {
  // Get list of all PIDs
  int num_pids = proc_listallpids(NULL, 0);
  if (num_pids <= 0) {
    snprintf(buffer, bufsize, "");
    return;
  }

  pid_t *pids = (pid_t *)malloc(sizeof(pid_t) * num_pids);
  if (!pids) {
    snprintf(buffer, bufsize, "");
    return;
  }

  num_pids = proc_listallpids(pids, sizeof(pid_t) * num_pids);
  if (num_pids <= 0) {
    free(pids);
    snprintf(buffer, bufsize, "");
    return;
  }

  // Collect GPU time for each process
  proc_gpu_info_t *all_procs = (proc_gpu_info_t *)malloc(sizeof(proc_gpu_info_t) * num_pids);
  if (!all_procs) {
    free(pids);
    snprintf(buffer, bufsize, "");
    return;
  }

  int valid_count = 0;
  for (int i = 0; i < num_pids; i++) {
    pid_t pid = pids[i];
    if (pid <= 0) continue;

    uint64_t gpu_time = get_process_gpu_time(pid);
    if (gpu_time == 0) continue;  // Skip processes with no GPU usage

    // Get process name
    char name[256] = {0};
    proc_name(pid, name, sizeof(name));
    if (name[0] == '\0') continue;

    all_procs[valid_count].pid = pid;
    strncpy(all_procs[valid_count].name, name, sizeof(all_procs[valid_count].name) - 1);
    all_procs[valid_count].gpu_time = gpu_time;
    valid_count++;
  }

  // Sort by GPU time descending
  qsort(all_procs, valid_count, sizeof(proc_gpu_info_t), compare_gpu_time);

  // Format top 10 as semicolon-separated string: "name1:time1;name2:time2;..."
  buffer[0] = '\0';
  int count = valid_count < MAX_TOP_PROCS ? valid_count : MAX_TOP_PROCS;
  size_t offset = 0;
  for (int i = 0; i < count && offset < bufsize - 1; i++) {
    int written = snprintf(buffer + offset, bufsize - offset, "%s%s:%llu",
                           i > 0 ? ";" : "",
                           all_procs[i].name,
                           (unsigned long long)all_procs[i].gpu_time);
    if (written > 0) offset += written;
  }

  free(all_procs);
  free(pids);
}

static int clamp_int(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

typedef struct __IOHIDEvent *IOHIDEventRef;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator,
                                                               int type,
                                                               CFDictionaryRef options);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service,
                                          int32_t eventType,
                                          int64_t timestamp,
                                          uint32_t options);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

static IOHIDEventSystemClientRef hid_client = NULL;
static CFArrayRef hid_services = NULL;

static bool ensure_hid_services(void) {
  if (hid_services) return true;

  hid_client = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, 1, NULL);
  if (!hid_client) return false;

  hid_services = IOHIDEventSystemClientCopyServices(hid_client);
  if (!hid_services) {
    CFRelease(hid_client);
    hid_client = NULL;
    return false;
  }
  return true;
}

static bool cfstring_contains(CFTypeRef value, const char *needle) {
  if (!value || CFGetTypeID(value) != CFStringGetTypeID() || !needle) return false;

  char buffer[256];
  if (!CFStringGetCString((CFStringRef)value, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
    return false;
  }
  return strstr(buffer, needle) != NULL;
}

static double read_hid_service_temperature(IOHIDServiceClientRef service) {
  enum { kHIDTemperatureEventType = 15 };
  const int32_t field = (kHIDTemperatureEventType << 16);

  IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kHIDTemperatureEventType, 0, 0);
  if (!event) return -1.0;

  double temp = IOHIDEventGetFloatValue(event, field);
  CFRelease(event);

  if (!isfinite(temp) || temp <= 0.0) return -1.0;
  return temp;
}

static void read_temperatures(int *cpu_temp, int *gpu_temp) {
  if (cpu_temp) *cpu_temp = -1;
  if (gpu_temp) *gpu_temp = -1;
  if (!ensure_hid_services()) return;

  double cpu_sum = 0.0;
  int cpu_count = 0;
  double gpu_max = -1.0;

  CFIndex count = CFArrayGetCount(hid_services);
  for (CFIndex i = 0; i < count; i++) {
    IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(hid_services, i);
    if (!IOHIDServiceClientConformsTo(service, 0xff00, 5)) continue;

    CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR(kIOHIDProductKey));
    bool is_tdie = cfstring_contains(product, "PMU tdie");
    bool is_tdev = cfstring_contains(product, "PMU tdev");

    if (is_tdie || is_tdev) {
      double temp = read_hid_service_temperature(service);
      if (temp > 0.0) {
        if (is_tdie) {
          cpu_sum += temp;
          cpu_count++;
        }
        if (is_tdev && temp > gpu_max) {
          gpu_max = temp;
        }
      }
    }

    if (product) CFRelease(product);
  }

  if (cpu_temp && cpu_count > 0) {
    *cpu_temp = (int)lround(cpu_sum / (double)cpu_count);
  }
  if (gpu_temp && gpu_max > 0.0) {
    *gpu_temp = (int)lround(gpu_max);
  }
}

static bool read_memory_stats(uint64_t *used_bytes, uint64_t *total_bytes, int *percent) {
  if (!used_bytes || !total_bytes || !percent) return false;

  uint64_t total = 0;
  size_t total_len = sizeof(total);
  if (sysctlbyname("hw.memsize", &total, &total_len, NULL, 0) != 0) return false;

  mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
  vm_statistics64_data_t vmstat;
  if (host_statistics64(mach_host_self(),
                        HOST_VM_INFO64,
                        (host_info64_t)&vmstat,
                        &count) != KERN_SUCCESS) {
    return false;
  }

  mach_port_t host = mach_host_self();
  vm_size_t page_size = 0;
  if (host_page_size(host, &page_size) != KERN_SUCCESS) return false;

  uint64_t used_pages = (uint64_t)vmstat.active_count + (uint64_t)vmstat.wire_count + (uint64_t)vmstat.compressor_page_count;
  uint64_t used = used_pages * (uint64_t)page_size;
  int pct = total > 0 ? (int)((double)used / (double)total * 100.0) : 0;

  *used_bytes = used;
  *total_bytes = total;
  *percent = clamp_int(pct, 0, 100);
  return true;
}

static int read_gpu_utilization(void) {
  io_iterator_t iterator;
  if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                   IOServiceMatching("IOAccelerator"),
                                   &iterator) != KERN_SUCCESS) {
    return -1;
  }

  int best = -1;
  io_object_t service;
  while ((service = IOIteratorNext(iterator))) {
    CFMutableDictionaryRef props = NULL;
    if (IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
      CFDictionaryRef stats = (CFDictionaryRef)CFDictionaryGetValue(props, CFSTR("PerformanceStatistics"));
      if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
        CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(stats, CFSTR("Device Utilization %"));
        if (!num) num = (CFNumberRef)CFDictionaryGetValue(stats, CFSTR("Renderer Utilization %"));
        if (num && CFGetTypeID(num) == CFNumberGetTypeID()) {
          int value = 0;
          if (CFNumberGetValue(num, kCFNumberIntType, &value)) {
            if (value > best) best = value;
          }
        }
      }
      CFRelease(props);
    }
    IOObjectRelease(service);
  }
  IOObjectRelease(iterator);

  return (best >= 0) ? clamp_int(best, 0, 100) : -1;
}

int main(int argc, char **argv) {
  float update_freq;
  if (argc < 3 || (sscanf(argv[2], "%f", &update_freq) != 1)) {
    printf("Usage: %s \"<event-name>\" \"<event_freq>\"\n", argv[0]);
    return 1;
  }

  alarm(0);
  struct cpu cpu;
  cpu_init(&cpu);

  char event_message[256];
  snprintf(event_message, sizeof(event_message), "--add event '%s'", argv[1]);
  sketchybar(event_message);

  char trigger_message[4096];
  char gpu_procs_buffer[2048];
  for (;;) {
    cpu_update(&cpu);

    uint64_t mem_used = 0;
    uint64_t mem_total = 0;
    int mem_percent = -1;
    bool mem_ok = read_memory_stats(&mem_used, &mem_total, &mem_percent);

    int gpu_util = read_gpu_utilization();
    int cpu_temp = -1;
    int gpu_temp = -1;
    read_temperatures(&cpu_temp, &gpu_temp);

    // Get top GPU processes
    get_top_gpu_processes(gpu_procs_buffer, sizeof(gpu_procs_buffer));

    snprintf(trigger_message,
             sizeof(trigger_message),
             "--trigger '%s' "
             "cpu_user='%d' "
             "cpu_sys='%d' "
             "cpu_total='%d' "
             "mem_used_percent='%d' "
             "mem_used_bytes='%llu' "
             "mem_total_bytes='%llu' "
             "gpu_util='%d' "
             "cpu_temp='%d' "
             "gpu_temp='%d' "
             "gpu_procs='%s'",
             argv[1],
             cpu.user_load,
             cpu.sys_load,
             cpu.total_load,
             mem_ok ? mem_percent : -1,
             (unsigned long long)(mem_ok ? mem_used : 0ULL),
             (unsigned long long)(mem_ok ? mem_total : 0ULL),
             gpu_util,
             cpu_temp,
             gpu_temp,
             gpu_procs_buffer);

    sketchybar(trigger_message);

    usleep((useconds_t)(update_freq * 1000000.0f));
  }
  return 0;
}
