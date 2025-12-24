#import <Foundation/Foundation.h>
#import <CoreWLAN/CoreWLAN.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <string.h>

static void set_string(NSMutableDictionary *dict, NSString *key, NSString *value) {
  if (value && value.length > 0) {
    dict[key] = value;
  }
}

static void set_number(NSMutableDictionary *dict, NSString *key, NSNumber *value) {
  if (value) {
    dict[key] = value;
  }
}

static NSString *string_from_phy_mode(CWPHYMode mode) {
  switch (mode) {
    case kCWPHYMode11a: return @"11a";
    case kCWPHYMode11b: return @"11b";
    case kCWPHYMode11g: return @"11g";
    case kCWPHYMode11n: return @"11n";
    case kCWPHYMode11ac: return @"11ac";
    case kCWPHYMode11ax: return @"11ax";
    default: return nil;
  }
}

static NSString *string_from_security(CWSecurity security) {
  switch (security) {
    case kCWSecurityNone: return @"Open";
    case kCWSecurityWEP: return @"WEP";
    case kCWSecurityWPAPersonal: return @"WPA Personal";
    case kCWSecurityWPAPersonalMixed: return @"WPA/WPA2 Personal";
    case kCWSecurityWPA2Personal: return @"WPA2 Personal";
    case kCWSecurityWPA3Personal: return @"WPA3 Personal";
    case kCWSecurityWPA3Transition: return @"WPA2/WPA3 Personal";
    case kCWSecurityDynamicWEP: return @"Dynamic WEP";
    case kCWSecurityWPAEnterprise: return @"WPA Enterprise";
    case kCWSecurityWPAEnterpriseMixed: return @"WPA/WPA2 Enterprise";
    case kCWSecurityWPA2Enterprise: return @"WPA2 Enterprise";
    case kCWSecurityWPA3Enterprise: return @"WPA3 Enterprise";
    case kCWSecurityOWE: return @"OWE";
    case kCWSecurityOWETransition: return @"OWE Transition";
    case kCWSecurityPersonal: return @"Personal";
    case kCWSecurityEnterprise: return @"Enterprise";
    default: return nil;
  }
}

static NSString *string_from_channel_width(CWChannelWidth width) {
  switch (width) {
    case kCWChannelWidth20MHz: return @"20MHz";
    case kCWChannelWidth40MHz: return @"40MHz";
    case kCWChannelWidth80MHz: return @"80MHz";
    case kCWChannelWidth160MHz: return @"160MHz";
    default: return nil;
  }
}

static NSString *string_from_channel_band(CWChannelBand band) {
  switch (band) {
    case kCWChannelBand2GHz: return @"2.4GHz";
    case kCWChannelBand5GHz: return @"5GHz";
    case kCWChannelBand6GHz: return @"6GHz";
    default: return nil;
  }
}

static NSString *string_from_channel(CWChannel *channel) {
  if (!channel) return nil;
  NSString *width = string_from_channel_width(channel.channelWidth);
  NSString *band = string_from_channel_band(channel.channelBand);
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  if (width) [parts addObject:width];
  if (band) [parts addObject:band];
  if (parts.count > 0) {
    return [NSString stringWithFormat:@"%ld (%@)", (long)channel.channelNumber, [parts componentsJoinedByString:@", "]];
  }
  return [NSString stringWithFormat:@"%ld", (long)channel.channelNumber];
}

static NSString *string_from_interface_mode(CWInterfaceMode mode) {
  switch (mode) {
    case kCWInterfaceModeStation: return @"Station";
    case kCWInterfaceModeIBSS: return @"IBSS";
    case kCWInterfaceModeHostAP: return @"HostAP";
    default: return nil;
  }
}

static NSString *copy_primary_interface(SCDynamicStoreRef store) {
  if (!store) return nil;
  CFStringRef keys[] = {
    CFSTR("State:/Network/Global/IPv4"),
    CFSTR("State:/Network/Global/IPv6"),
  };
  for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
    CFDictionaryRef dict = SCDynamicStoreCopyValue(store, keys[i]);
    if (!dict) continue;
    CFStringRef iface = CFDictionaryGetValue(dict, CFSTR("PrimaryInterface"));
    NSString *name = nil;
    if (iface && CFGetTypeID(iface) == CFStringGetTypeID()) {
      name = [(__bridge NSString *)iface copy];
    }
    CFRelease(dict);
    if (name.length > 0) return name;
  }
  return nil;
}

static NSString *copy_router(SCDynamicStoreRef store, NSString *interface_name) {
  if (!store) return nil;
  CFDictionaryRef dict = NULL;
  NSString *value = nil;
  if (interface_name.length > 0) {
    NSString *key = [NSString stringWithFormat:@"State:/Network/Interface/%@/IPv4", interface_name];
    dict = SCDynamicStoreCopyValue(store, (__bridge CFStringRef)key);
    if (dict) {
      CFStringRef router = CFDictionaryGetValue(dict, CFSTR("Router"));
      if (router && CFGetTypeID(router) == CFStringGetTypeID()) {
        value = [(__bridge NSString *)router copy];
      }
      CFRelease(dict);
      if (value.length > 0) return value;
    }
  }
  dict = SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4"));
  if (!dict) return nil;
  CFStringRef router = CFDictionaryGetValue(dict, CFSTR("Router"));
  if (router && CFGetTypeID(router) == CFStringGetTypeID()) {
    value = [(__bridge NSString *)router copy];
  }
  CFRelease(dict);
  return value;
}

static NSString *copy_airport_ssid(SCDynamicStoreRef store, NSString *interface_name) {
  if (!store || interface_name.length == 0) return nil;
  NSString *key = [NSString stringWithFormat:@"State:/Network/Interface/%@/AirPort", interface_name];
  CFDictionaryRef dict = SCDynamicStoreCopyValue(store, (__bridge CFStringRef)key);
  if (!dict) return nil;
  CFStringRef ssid = CFDictionaryGetValue(dict, CFSTR("SSID_STR"));
  NSString *value = nil;
  if (ssid && CFGetTypeID(ssid) == CFStringGetTypeID()) {
    value = [(__bridge NSString *)ssid copy];
  }
  CFRelease(dict);
  return value;
}

static BOOL is_safe_interface_name(NSString *name) {
  if (name.length == 0) return NO;
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
  return [name rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

static void copy_ipconfig_ssid_bssid(NSString *interface_name, NSString **ssid_out, NSString **bssid_out) {
  if (!interface_name || !is_safe_interface_name(interface_name)) return;
  NSString *cmd = [NSString stringWithFormat:@"/usr/sbin/ipconfig getsummary %@", interface_name];
  FILE *pipe = popen(cmd.UTF8String, "r");
  if (!pipe) return;
  char line[512];
  NSString *ssid = nil;
  NSString *bssid = nil;
  NSCharacterSet *trim = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  while (fgets(line, sizeof(line), pipe)) {
    NSString *line_str = [NSString stringWithUTF8String:line];
    if (!line_str) continue;
    line_str = [line_str stringByTrimmingCharactersInSet:trim];
    if (ssid.length == 0 && [line_str hasPrefix:@"SSID"]) {
      NSRange colon = [line_str rangeOfString:@":"];
      if (colon.location != NSNotFound) {
        NSString *value = [[line_str substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:trim];
        if (value.length > 0) ssid = value;
      }
    } else if (bssid.length == 0 && [line_str hasPrefix:@"BSSID"]) {
      NSRange colon = [line_str rangeOfString:@":"];
      if (colon.location != NSNotFound) {
        NSString *value = [[line_str substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:trim];
        if (value.length > 0) bssid = value;
      }
    }
    if (ssid.length > 0 && bssid.length > 0) break;
  }
  pclose(pipe);
  if (ssid_out && ssid.length > 0) *ssid_out = ssid;
  if (bssid_out && bssid.length > 0) *bssid_out = bssid;
}

static void add_ipv4_info(NSMutableDictionary *dict, const char *ifname) {
  if (!ifname || ifname[0] == '\0') return;
  struct ifaddrs *ifaddr = NULL;
  if (getifaddrs(&ifaddr) != 0 || !ifaddr) return;
  for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
    if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
    if (strcmp(ifa->ifa_name, ifname) != 0) continue;
    char addr_buf[INET_ADDRSTRLEN] = { 0 };
    struct sockaddr_in *addr = (struct sockaddr_in *)ifa->ifa_addr;
    if (inet_ntop(AF_INET, &addr->sin_addr, addr_buf, sizeof(addr_buf))) {
      set_string(dict, @"ip", [NSString stringWithUTF8String:addr_buf]);
    }
    if (ifa->ifa_netmask) {
      char mask_buf[INET_ADDRSTRLEN] = { 0 };
      struct sockaddr_in *mask = (struct sockaddr_in *)ifa->ifa_netmask;
      if (inet_ntop(AF_INET, &mask->sin_addr, mask_buf, sizeof(mask_buf))) {
        set_string(dict, @"subnet_mask", [NSString stringWithUTF8String:mask_buf]);
      }
    }
    break;
  }
  freeifaddrs(ifaddr);
}

int main(int argc, char **argv) {
  @autoreleasepool {
    NSString *interface_arg = nil;
    for (int i = 1; i < argc; i++) {
      if (!interface_arg) {
        interface_arg = [NSString stringWithUTF8String:argv[i]];
      }
    }

    BOOL auto_mode = (interface_arg.length == 0) || [interface_arg isEqualToString:@"auto"] || [interface_arg isEqualToString:@"default"];
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("network_info"), NULL, NULL);
    NSString *interface_name = nil;
    if (auto_mode) {
      interface_name = copy_primary_interface(store);
    } else {
      interface_name = interface_arg;
    }

    CWWiFiClient *client = [CWWiFiClient sharedWiFiClient];
    CWInterface *iface = nil;
    if (interface_name.length > 0) {
      iface = [client interfaceWithName:interface_name];
    } else {
      iface = [client interface];
      if (iface.interfaceName.length > 0) {
        interface_name = iface.interfaceName;
      }
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (interface_name.length > 0) {
      set_string(info, @"interface", interface_name);
      add_ipv4_info(info, [interface_name UTF8String]);
    }

    CFStringRef computer_name = SCDynamicStoreCopyComputerName(NULL, NULL);
    if (computer_name) {
      set_string(info, @"hostname", (__bridge_transfer NSString *)computer_name);
    }

    if (iface) {
      NSString *ssid = iface.ssid;
      if (ssid.length == 0) {
        NSData *ssid_data = iface.ssidData;
        if (ssid_data.length > 0) {
          ssid = [[NSString alloc] initWithData:ssid_data encoding:NSUTF8StringEncoding];
          if (ssid.length == 0) {
            ssid = [[NSString alloc] initWithData:ssid_data encoding:NSISOLatin1StringEncoding];
          }
        }
      }
      if (ssid.length == 0) {
        ssid = copy_airport_ssid(store, interface_name);
      }
      NSString *bssid = iface.bssid;
      if (ssid.length == 0 || bssid.length == 0) {
        NSString *ipconfig_ssid = nil;
        NSString *ipconfig_bssid = nil;
        copy_ipconfig_ssid_bssid(interface_name, &ipconfig_ssid, &ipconfig_bssid);
        if (ssid.length == 0 && ipconfig_ssid.length > 0) ssid = ipconfig_ssid;
        if (bssid.length == 0 && ipconfig_bssid.length > 0) bssid = ipconfig_bssid;
      }
      set_string(info, @"ssid", ssid);
      set_string(info, @"bssid", bssid);
      set_string(info, @"country_code", iface.countryCode);
      set_string(info, @"adapter_mac", iface.hardwareAddress);

      NSString *phy = string_from_phy_mode(iface.activePHYMode);
      set_string(info, @"phy_mode", phy);

      NSString *channel = string_from_channel(iface.wlanChannel);
      set_string(info, @"channel", channel);

      NSString *security = string_from_security(iface.security);
      set_string(info, @"security", security);

      NSString *mode = string_from_interface_mode(iface.interfaceMode);
      set_string(info, @"interface_mode", mode);

      NSInteger rssi = iface.rssiValue;
      NSInteger noise = iface.noiseMeasurement;
      if (rssi != 0) {
        set_number(info, @"rssi", @(rssi));
      }
      if (noise != 0) {
        set_number(info, @"noise", @(noise));
      }
      if (rssi != 0 && noise != 0) {
        NSInteger snr = rssi - noise;
        set_number(info, @"snr", @(snr));
        set_string(info, @"signal_noise", [NSString stringWithFormat:@"%ld dBm / %ld dBm", (long)rssi, (long)noise]);
      }

      double tx_rate = iface.transmitRate;
      if (tx_rate > 0) {
        set_string(info, @"transmit_rate", [NSString stringWithFormat:@"%.0f Mbps", tx_rate]);
        set_number(info, @"transmit_rate_mbps", @(tx_rate));
      }

      NSInteger tx_power = iface.transmitPower;
      if (tx_power > 0) {
        set_string(info, @"transmit_power", [NSString stringWithFormat:@"%ld mW", (long)tx_power]);
        set_number(info, @"transmit_power_mw", @(tx_power));
      }
    }

    NSString *router = copy_router(store, interface_name);
    set_string(info, @"router", router);
    if (store) CFRelease(store);

    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:info options:0 error:&error];
    if (!json) {
      fprintf(stderr, "Failed to encode JSON: %s\n", error.localizedDescription.UTF8String);
      return 1;
    }
    fwrite(json.bytes, 1, json.length, stdout);
  }
  return 0;
}
