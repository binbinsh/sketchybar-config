#include "network_interface_resolver.h"

#include <SystemConfiguration/SCNetworkConfiguration.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <string.h>

#define MAX_INTERFACE_CANDIDATES 64

struct interface_candidate {
  char name[IF_NAMESIZE];
  int score;
};

static bool is_virtual_interface_name(const char *name) {
  static const char *prefixes[] = {
    "lo",
    "utun",
    "ipsec",
    "ppp",
    "tun",
    "tap",
    "gif",
    "stf",
    "llw",
    "awdl",
    "ap",
    "anpi",
    "bridge",
    "vnic",
    "vmnet",
    "feth",
  };

  if (!name || name[0] == '\0') return true;
  for (size_t i = 0; i < sizeof(prefixes) / sizeof(prefixes[0]); i++) {
    size_t prefix_len = strlen(prefixes[i]);
    if (strncmp(name, prefixes[i], prefix_len) == 0) return true;
  }
  return false;
}

static bool is_link_local_ipv4(const struct sockaddr_in *addr) {
  if (!addr) return false;
  uint32_t ip = ntohl(addr->sin_addr.s_addr);
  return (ip & 0xFFFF0000u) == 0xA9FE0000u;
}

static bool has_router_for_interface(SCDynamicStoreRef store, const char *ifname) {
  if (!store || !ifname || ifname[0] == '\0') return false;

  CFStringRef key = CFStringCreateWithFormat(NULL,
                                             NULL,
                                             CFSTR("State:/Network/Interface/%s/IPv4"),
                                             ifname);
  if (!key) return false;

  CFDictionaryRef dict = SCDynamicStoreCopyValue(store, key);
  CFRelease(key);
  if (!dict) return false;

  CFStringRef router = CFDictionaryGetValue(dict, CFSTR("Router"));
  bool has_router = router && (CFGetTypeID(router) == CFStringGetTypeID());
  CFRelease(dict);
  return has_router;
}

bool sb_copy_primary_interface(SCDynamicStoreRef store,
                               char *buffer,
                               size_t buffer_size) {
  if (!store || !buffer || buffer_size == 0) return false;

  buffer[0] = '\0';
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

static size_t find_candidate_index(struct interface_candidate *candidates,
                                   size_t count,
                                   const char *name) {
  for (size_t i = 0; i < count; i++) {
    if (strcmp(candidates[i].name, name) == 0) return i;
  }
  return SIZE_MAX;
}

static void upsert_candidate(struct interface_candidate *candidates,
                             size_t *count,
                             const char *name,
                             int score) {
  size_t index = find_candidate_index(candidates, *count, name);
  if (index != SIZE_MAX) {
    if (score > candidates[index].score) candidates[index].score = score;
    return;
  }

  if (*count >= MAX_INTERFACE_CANDIDATES) return;
  strlcpy(candidates[*count].name, name, sizeof(candidates[*count].name));
  candidates[*count].score = score;
  (*count)++;
}

static size_t collect_active_candidates(SCDynamicStoreRef store,
                                        const char *primary,
                                        struct interface_candidate *candidates) {
  struct ifaddrs *ifaddr = NULL;
  if (getifaddrs(&ifaddr) != 0 || !ifaddr) return 0;

  size_t count = 0;
  for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
    if (!ifa->ifa_name || !ifa->ifa_addr) continue;
    if (ifa->ifa_addr->sa_family != AF_INET) continue;
    if ((ifa->ifa_flags & (IFF_UP | IFF_RUNNING)) != (IFF_UP | IFF_RUNNING)) continue;
    if ((ifa->ifa_flags & (IFF_LOOPBACK | IFF_POINTOPOINT)) != 0) continue;
    if (is_virtual_interface_name(ifa->ifa_name)) continue;

    struct sockaddr_in *addr = (struct sockaddr_in *)ifa->ifa_addr;
    if (is_link_local_ipv4(addr)) continue;

    int score = 0;
    if (has_router_for_interface(store, ifa->ifa_name)) score += 100;
    if (strncmp(ifa->ifa_name, "en", 2) == 0) {
      score += 50;
    } else if (strncmp(ifa->ifa_name, "bond", 4) == 0) {
      score += 40;
    } else {
      score += 10;
    }
    if (primary && primary[0] != '\0' && strcmp(ifa->ifa_name, primary) == 0) {
      score += 25;
    }

    upsert_candidate(candidates, &count, ifa->ifa_name, score);
  }

  freeifaddrs(ifaddr);
  return count;
}

static bool copy_nonvirtual_service_bsd_name(SCNetworkInterfaceRef interface,
                                             char *buffer,
                                             size_t buffer_size) {
  if (!buffer || buffer_size == 0) return false;

  buffer[0] = '\0';
  for (SCNetworkInterfaceRef current = interface;
       current != NULL;
       current = SCNetworkInterfaceGetInterface(current)) {
    CFStringRef bsd_name = SCNetworkInterfaceGetBSDName(current);
    if (!bsd_name) continue;

    char name[IF_NAMESIZE] = { 0 };
    if (!CFStringGetCString(bsd_name, name, sizeof(name), kCFStringEncodingUTF8)) continue;
    if (is_virtual_interface_name(name)) continue;

    strlcpy(buffer, name, buffer_size);
    return true;
  }

  return false;
}

static bool pick_service_order_candidate(struct interface_candidate *candidates,
                                         size_t candidate_count,
                                         char *buffer,
                                         size_t buffer_size) {
  if (!buffer || buffer_size == 0 || candidate_count <= 1) return false;

  SCPreferencesRef prefs = SCPreferencesCreate(NULL, CFSTR("network_interface_resolver"), NULL);
  if (!prefs) return false;

  SCNetworkSetRef set = SCNetworkSetCopyCurrent(prefs);
  if (!set) {
    CFRelease(prefs);
    return false;
  }

  CFArrayRef service_order = SCNetworkSetGetServiceOrder(set);
  CFArrayRef services = SCNetworkSetCopyServices(set);
  bool found = false;

  if (service_order && services) {
    CFIndex order_count = CFArrayGetCount(service_order);
    CFIndex service_count = CFArrayGetCount(services);

    for (CFIndex i = 0; i < order_count && !found; i++) {
      CFStringRef wanted_id = CFArrayGetValueAtIndex(service_order, i);
      if (!wanted_id || CFGetTypeID(wanted_id) != CFStringGetTypeID()) continue;

      for (CFIndex j = 0; j < service_count; j++) {
        SCNetworkServiceRef service = (SCNetworkServiceRef)CFArrayGetValueAtIndex(services, j);
        CFStringRef service_id = SCNetworkServiceGetServiceID(service);
        if (!service_id || CFStringCompare(wanted_id, service_id, 0) != kCFCompareEqualTo) continue;

        char name[IF_NAMESIZE] = { 0 };
        if (!copy_nonvirtual_service_bsd_name(SCNetworkServiceGetInterface(service),
                                              name,
                                              sizeof(name))) {
          break;
        }

        if (find_candidate_index(candidates, candidate_count, name) != SIZE_MAX) {
          strlcpy(buffer, name, buffer_size);
          found = true;
        }
        break;
      }
    }
  }

  if (services) CFRelease(services);
  CFRelease(set);
  CFRelease(prefs);
  return found;
}

bool sb_resolve_effective_interface(SCDynamicStoreRef store,
                                    char *buffer,
                                    size_t buffer_size) {
  if (!buffer || buffer_size == 0) return false;

  buffer[0] = '\0';
  char primary[IF_NAMESIZE] = { 0 };
  bool has_primary = sb_copy_primary_interface(store, primary, sizeof(primary));

  if (has_primary && !is_virtual_interface_name(primary)) {
    strlcpy(buffer, primary, buffer_size);
    return true;
  }

  struct interface_candidate candidates[MAX_INTERFACE_CANDIDATES] = { 0 };
  size_t candidate_count = collect_active_candidates(store, primary, candidates);

  if (candidate_count == 1) {
    strlcpy(buffer, candidates[0].name, buffer_size);
    return true;
  }

  if (candidate_count > 1
      && pick_service_order_candidate(candidates, candidate_count, buffer, buffer_size)) {
    return true;
  }

  if (candidate_count > 0) {
    size_t best = 0;
    for (size_t i = 1; i < candidate_count; i++) {
      if (candidates[i].score > candidates[best].score) best = i;
    }
    strlcpy(buffer, candidates[best].name, buffer_size);
    return true;
  }

  if (has_primary) {
    strlcpy(buffer, primary, buffer_size);
    return true;
  }

  return false;
}
