#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include "network.h"
#include "../sketchybar.h"

static bool resolve_primary_interface(SCDynamicStoreRef store,
                                      char* buffer,
                                      size_t buffer_size) {
  if (!store || !buffer || buffer_size == 0) return false;
  CFStringRef keys[] = {
    CFSTR("State:/Network/Global/IPv4"),
    CFSTR("State:/Network/Global/IPv6"),
  };
  for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
    CFDictionaryRef dict = SCDynamicStoreCopyValue(store, keys[i]);
    if (!dict) continue;
    CFStringRef iface = CFDictionaryGetValue(dict, CFSTR("PrimaryInterface"));
    bool ok = false;
    if (iface && CFGetTypeID(iface) == CFStringGetTypeID()) {
      ok = CFStringGetCString(iface, buffer, buffer_size, kCFStringEncodingUTF8);
    }
    CFRelease(dict);
    if (ok && buffer[0] != '\0') return true;
  }
  return false;
}

int main (int argc, char** argv) {
  float update_freq;
  if (argc < 4 || (sscanf(argv[3], "%f", &update_freq) != 1)) {
    printf("Usage: %s \"<interface|auto>\" \"<event-name>\" \"<event_freq>\"\n", argv[0]);
    exit(1);
  }

  bool auto_mode = (strcmp(argv[1], "auto") == 0) || (strcmp(argv[1], "default") == 0);
  SCDynamicStoreRef store = NULL;
  char ifname[IF_NAMESIZE] = { 0 };
  const char* interface_name = argv[1];
  if (auto_mode) {
    store = SCDynamicStoreCreate(NULL, CFSTR("network_load"), NULL, NULL);
    if (!store || !resolve_primary_interface(store, ifname, sizeof(ifname))) {
      fprintf(stderr, "Failed to resolve primary interface\n");
      if (store) CFRelease(store);
      return 1;
    }
    interface_name = ifname;
  }

  alarm(0);
  // Setup the event in sketchybar
  char event_message[512];
  snprintf(event_message, 512, "--add event '%s'", argv[2]);
  sketchybar(event_message);

  struct network network;
  if (!network_init(&network, interface_name)) {
    fprintf(stderr, "Interface not found: %s\n", interface_name);
    if (store) CFRelease(store);
    return 1;
  }
  char trigger_message[512];
  for (;;) {
    if (auto_mode) {
      char current[IF_NAMESIZE] = { 0 };
      if (resolve_primary_interface(store, current, sizeof(current))
          && strcmp(current, ifname) != 0) {
        strlcpy(ifname, current, sizeof(ifname));
        if (!network_init(&network, ifname)) {
          fprintf(stderr, "Interface not found: %s\n", ifname);
          usleep(update_freq * 1000000);
          continue;
        }
      }
    }
    // Acquire new info
    network_update(&network);

    // Prepare the event message
    snprintf(trigger_message,
             512,
             "--trigger '%s' upload='%.2f' download='%.2f'",
             argv[2],
             network.up_mbps,
             network.down_mbps);

    // Trigger the event
    sketchybar(trigger_message);

    // Wait
    usleep(update_freq * 1000000);
  }
  return 0;
}
