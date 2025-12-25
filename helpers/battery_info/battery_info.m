#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>

static void set_string(NSMutableDictionary *dict, NSString *key, NSString *value) {
  if (value && value.length > 0) dict[key] = value;
}

static void set_number(NSMutableDictionary *dict, NSString *key, NSNumber *value) {
  if (value) dict[key] = value;
}

static void set_bool(NSMutableDictionary *dict, NSString *key, BOOL value, BOOL has_value) {
  if (has_value) dict[key] = @(value);
}

static NSNumber *number_from_cf(CFTypeRef value) {
  if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) return nil;
  int64_t out = 0;
  if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &out)) return nil;
  return @(out);
}

static NSNumber *bool_from_cf(CFTypeRef value, BOOL *has_value) {
  if (has_value) *has_value = NO;
  if (!value || CFGetTypeID(value) != CFBooleanGetTypeID()) return nil;
  if (has_value) *has_value = YES;
  return @(((CFBooleanRef)value) == kCFBooleanTrue);
}

static NSString *string_from_cf(CFTypeRef value) {
  if (!value || CFGetTypeID(value) != CFStringGetTypeID()) return nil;
  return (__bridge NSString *)value;
}

static NSArray<NSNumber *> *number_array_from_cf(CFTypeRef value) {
  if (!value || CFGetTypeID(value) != CFArrayGetTypeID()) return nil;
  CFArrayRef arr = (CFArrayRef)value;
  CFIndex count = CFArrayGetCount(arr);
  if (count <= 0) return @[];
  NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
  for (CFIndex i = 0; i < count; i++) {
    CFTypeRef elem = CFArrayGetValueAtIndex(arr, i);
    NSNumber *n = number_from_cf(elem);
    if (n) [out addObject:n];
  }
  return out;
}

static void add_power_source_info(NSMutableDictionary *info) {
  CFTypeRef blob = IOPSCopyPowerSourcesInfo();
  if (!blob) return;

  CFArrayRef list = IOPSCopyPowerSourcesList(blob);
  if (!list) {
    CFRelease(blob);
    return;
  }

  CFIndex count = CFArrayGetCount(list);
  for (CFIndex i = 0; i < count; i++) {
    CFTypeRef ps = CFArrayGetValueAtIndex(list, i);
    if (!ps) continue;

    CFDictionaryRef desc = IOPSGetPowerSourceDescription(blob, ps);
    if (!desc || CFGetTypeID(desc) != CFDictionaryGetTypeID()) continue;

    // Prefer internal battery if present.
    NSString *type = string_from_cf(CFDictionaryGetValue(desc, CFSTR(kIOPSTypeKey)));
    // kIOPSInternalBatteryType is a C-string on some SDKs; compare by value.
    if (type && ![type isEqualToString:@"InternalBattery"]) {
      continue;
    }

    NSNumber *cur = number_from_cf(CFDictionaryGetValue(desc, CFSTR(kIOPSCurrentCapacityKey)));
    NSNumber *max = number_from_cf(CFDictionaryGetValue(desc, CFSTR(kIOPSMaxCapacityKey)));
    if (cur && max && max.longLongValue > 0) {
      int64_t pct = (int64_t)llround((double)cur.longLongValue * 100.0 / (double)max.longLongValue);
      if (pct < 0) pct = 0;
      if (pct > 100) pct = 100;
      set_number(info, @"percent", @(pct));
    }

    BOOL has_b = NO;
    NSNumber *is_charging = bool_from_cf(CFDictionaryGetValue(desc, CFSTR(kIOPSIsChargingKey)), &has_b);
    if (has_b) set_bool(info, @"is_charging", is_charging.boolValue, YES);

    has_b = NO;
    NSNumber *is_charged = bool_from_cf(CFDictionaryGetValue(desc, CFSTR(kIOPSIsChargedKey)), &has_b);
    if (has_b) set_bool(info, @"is_charged", is_charged.boolValue, YES);

    NSNumber *time_to_empty = number_from_cf(CFDictionaryGetValue(desc, CFSTR(kIOPSTimeToEmptyKey)));
    if (time_to_empty && time_to_empty.longLongValue >= 0) {
      set_number(info, @"time_to_empty_min", time_to_empty);
    }

    NSNumber *time_to_full = number_from_cf(CFDictionaryGetValue(desc, CFSTR(kIOPSTimeToFullChargeKey)));
    if (time_to_full && time_to_full.longLongValue >= 0) {
      set_number(info, @"time_to_full_min", time_to_full);
    }

    NSString *state = string_from_cf(CFDictionaryGetValue(desc, CFSTR(kIOPSPowerSourceStateKey)));
    if (state) {
      // kIOPSACPowerValue / kIOPSBatteryPowerValue may be C-strings; compare by value.
      if ([state isEqualToString:@"AC Power"]) {
        set_string(info, @"power_source", @"AC");
      } else if ([state isEqualToString:@"Battery Power"]) {
        set_string(info, @"power_source", @"Battery");
      } else {
        set_string(info, @"power_source", state);
      }
    }

    // Only one internal battery expected; stop after first match.
    break;
  }

  CFRelease(list);
  CFRelease(blob);
}

static void add_smart_battery_info(NSMutableDictionary *info) {
  io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
  if (!service) return;

  CFMutableDictionaryRef props = NULL;
  kern_return_t kr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0);
  IOObjectRelease(service);
  if (kr != KERN_SUCCESS || !props) return;

  NSNumber *cycle = number_from_cf(CFDictionaryGetValue(props, CFSTR("CycleCount")));
  set_number(info, @"cycle_count", cycle);

  NSNumber *design = number_from_cf(CFDictionaryGetValue(props, CFSTR("DesignCapacity")));
  set_number(info, @"design_capacity", design);

  NSNumber *design_cycles = number_from_cf(CFDictionaryGetValue(props, CFSTR("DesignCycleCount9C")));
  set_number(info, @"design_cycle_count", design_cycles);

  // Common state flags.
  BOOL has_b = NO;
  NSNumber *critical = bool_from_cf(CFDictionaryGetValue(props, CFSTR("AtCriticalLevel")), &has_b);
  if (has_b) set_bool(info, @"critical", critical.boolValue, YES);

  has_b = NO;
  NSNumber *battery_installed = bool_from_cf(CFDictionaryGetValue(props, CFSTR("BatteryInstalled")), &has_b);
  if (has_b) set_bool(info, @"battery_installed", battery_installed.boolValue, YES);

  has_b = NO;
  NSNumber *fully_charged = bool_from_cf(CFDictionaryGetValue(props, CFSTR("FullyCharged")), &has_b);
  if (has_b) set_bool(info, @"fully_charged", fully_charged.boolValue, YES);

  has_b = NO;
  NSNumber *external_connected = bool_from_cf(CFDictionaryGetValue(props, CFSTR("ExternalConnected")), &has_b);
  if (has_b) set_bool(info, @"external_connected", external_connected.boolValue, YES);

  has_b = NO;
  NSNumber *external_charge_capable = bool_from_cf(CFDictionaryGetValue(props, CFSTR("ExternalChargeCapable")), &has_b);
  if (has_b) set_bool(info, @"external_charge_capable", external_charge_capable.boolValue, YES);

  NSNumber *max = number_from_cf(CFDictionaryGetValue(props, CFSTR("MaxCapacity")));
  set_number(info, @"max_capacity", max);

  NSNumber *cur = number_from_cf(CFDictionaryGetValue(props, CFSTR("CurrentCapacity")));
  set_number(info, @"current_capacity", cur);

  NSNumber *raw_cur = number_from_cf(CFDictionaryGetValue(props, CFSTR("AppleRawCurrentCapacity")));
  set_number(info, @"raw_current_capacity", raw_cur);

  NSNumber *raw_max = number_from_cf(CFDictionaryGetValue(props, CFSTR("AppleRawMaxCapacity")));
  set_number(info, @"raw_max_capacity", raw_max);

  NSNumber *nominal = number_from_cf(CFDictionaryGetValue(props, CFSTR("NominalChargeCapacity")));
  set_number(info, @"nominal_capacity", nominal);

  NSNumber *voltage = number_from_cf(CFDictionaryGetValue(props, CFSTR("Voltage")));
  set_number(info, @"voltage_mv", voltage);

  NSNumber *amperage = number_from_cf(CFDictionaryGetValue(props, CFSTR("Amperage")));
  set_number(info, @"amperage_ma", amperage);

  NSNumber *instant_amperage = number_from_cf(CFDictionaryGetValue(props, CFSTR("InstantAmperage")));
  set_number(info, @"instant_amperage_ma", instant_amperage);

  NSNumber *failure = number_from_cf(CFDictionaryGetValue(props, CFSTR("PermanentFailureStatus")));
  set_number(info, @"permanent_failure_status", failure);

  has_b = NO;
  NSNumber *is_charging = bool_from_cf(CFDictionaryGetValue(props, CFSTR("IsCharging")), &has_b);
  if (has_b) set_bool(info, @"is_charging_smart", is_charging.boolValue, YES);

  NSString *serial = string_from_cf(CFDictionaryGetValue(props, CFSTR("Serial")));
  set_string(info, @"serial", serial);

  NSString *device = string_from_cf(CFDictionaryGetValue(props, CFSTR("DeviceName")));
  set_string(info, @"device_name", device);

  NSNumber *fw = number_from_cf(CFDictionaryGetValue(props, CFSTR("GasGaugeFirmwareVersion")));
  set_number(info, @"gas_gauge_fw", fw);

  // Raw time fields (often 65535 when unknown).
  NSNumber *time_remaining = number_from_cf(CFDictionaryGetValue(props, CFSTR("TimeRemaining")));
  set_number(info, @"time_remaining_raw", time_remaining);
  NSNumber *avg_empty = number_from_cf(CFDictionaryGetValue(props, CFSTR("AvgTimeToEmpty")));
  set_number(info, @"avg_time_to_empty_raw", avg_empty);
  NSNumber *avg_full = number_from_cf(CFDictionaryGetValue(props, CFSTR("AvgTimeToFull")));
  set_number(info, @"avg_time_to_full_raw", avg_full);

  NSNumber *pack_reserve = number_from_cf(CFDictionaryGetValue(props, CFSTR("PackReserve")));
  set_number(info, @"pack_reserve", pack_reserve);

  CFTypeRef adapter_val = CFDictionaryGetValue(props, CFSTR("AdapterDetails"));
  if (adapter_val && CFGetTypeID(adapter_val) == CFDictionaryGetTypeID()) {
    CFDictionaryRef adapter = (CFDictionaryRef)adapter_val;
    NSNumber *watts = number_from_cf(CFDictionaryGetValue(adapter, CFSTR("Watts")));
    set_number(info, @"adapter_watts", watts);
    NSNumber *adapter_voltage = number_from_cf(CFDictionaryGetValue(adapter, CFSTR("AdapterVoltage")));
    set_number(info, @"adapter_voltage_mv", adapter_voltage);
    NSNumber *adapter_current = number_from_cf(CFDictionaryGetValue(adapter, CFSTR("Current")));
    set_number(info, @"adapter_current_ma", adapter_current);
    NSString *desc = string_from_cf(CFDictionaryGetValue(adapter, CFSTR("Description")));
    set_string(info, @"adapter_desc", desc);
  }

  CFTypeRef charger_val = CFDictionaryGetValue(props, CFSTR("ChargerData"));
  if (charger_val && CFGetTypeID(charger_val) == CFDictionaryGetTypeID()) {
    CFDictionaryRef charger = (CFDictionaryRef)charger_val;
    set_number(info, @"charger_voltage_mv", number_from_cf(CFDictionaryGetValue(charger, CFSTR("ChargingVoltage"))));
    set_number(info, @"charger_current_ma", number_from_cf(CFDictionaryGetValue(charger, CFSTR("ChargingCurrent"))));
    set_number(info, @"charger_id", number_from_cf(CFDictionaryGetValue(charger, CFSTR("ChargerID"))));
    set_number(info, @"charger_not_charging_reason", number_from_cf(CFDictionaryGetValue(charger, CFSTR("NotChargingReason"))));
    set_number(info, @"charger_slow_charging_reason", number_from_cf(CFDictionaryGetValue(charger, CFSTR("SlowChargingReason"))));
    set_number(info, @"charger_inhibit_reason", number_from_cf(CFDictionaryGetValue(charger, CFSTR("ChargerInhibitReason"))));
  }

  CFTypeRef batt_val = CFDictionaryGetValue(props, CFSTR("BatteryData"));
  if (batt_val && CFGetTypeID(batt_val) == CFDictionaryGetTypeID()) {
    CFDictionaryRef batt = (CFDictionaryRef)batt_val;
    NSArray<NSNumber *> *cells = number_array_from_cf(CFDictionaryGetValue(batt, CFSTR("CellVoltage")));
    if (cells && cells.count > 0) {
      info[@"cell_voltage_mv"] = cells;
      int64_t min_v = INT64_MAX;
      int64_t max_v = INT64_MIN;
      for (NSNumber *n in cells) {
        int64_t v = n.longLongValue;
        if (v < min_v) min_v = v;
        if (v > max_v) max_v = v;
      }
      if (min_v != INT64_MAX && max_v != INT64_MIN) {
        set_number(info, @"cell_voltage_min_mv", @(min_v));
        set_number(info, @"cell_voltage_max_mv", @(max_v));
        set_number(info, @"cell_voltage_delta_mv", @(max_v - min_v));
      }
    }

    NSNumber *soc = number_from_cf(CFDictionaryGetValue(batt, CFSTR("StateOfCharge")));
    set_number(info, @"soc_percent", soc);
    set_number(info, @"daily_min_soc", number_from_cf(CFDictionaryGetValue(batt, CFSTR("DailyMinSoc"))));
    set_number(info, @"daily_max_soc", number_from_cf(CFDictionaryGetValue(batt, CFSTR("DailyMaxSoc"))));
  }

  CFTypeRef telemetry_val = CFDictionaryGetValue(props, CFSTR("PowerTelemetryData"));
  if (telemetry_val && CFGetTypeID(telemetry_val) == CFDictionaryGetTypeID()) {
    CFDictionaryRef tele = (CFDictionaryRef)telemetry_val;
    NSNumber *sys_v = number_from_cf(CFDictionaryGetValue(tele, CFSTR("SystemVoltageIn")));
    NSNumber *sys_i = number_from_cf(CFDictionaryGetValue(tele, CFSTR("SystemCurrentIn")));
    NSNumber *sys_p = number_from_cf(CFDictionaryGetValue(tele, CFSTR("SystemPowerIn")));
    set_number(info, @"telemetry_system_voltage_in_mv", sys_v);
    set_number(info, @"telemetry_system_current_in_ma", sys_i);
    if (sys_p) {
      double w = (double)sys_p.longLongValue / 1000.0;
      double rounded = round(w * 10.0) / 10.0;
      set_number(info, @"telemetry_system_power_in_w", @(rounded));
    }
    set_number(info, @"telemetry_system_load", number_from_cf(CFDictionaryGetValue(tele, CFSTR("SystemLoad"))));
    set_number(info, @"telemetry_battery_power", number_from_cf(CFDictionaryGetValue(tele, CFSTR("BatteryPower"))));
  }

  NSString *health = string_from_cf(CFDictionaryGetValue(props, CFSTR("BatteryHealth")));
  set_string(info, @"health", health);

  NSNumber *temp_raw = number_from_cf(CFDictionaryGetValue(props, CFSTR("Temperature")));
  if (temp_raw) {
    set_number(info, @"temperature_raw", temp_raw);
    // Best-effort conversion: many Macs expose Temperature as 0.1 Kelvin.
    double raw = (double)temp_raw.longLongValue;
    if (raw > 1000.0) {
      double c = (raw / 10.0) - 273.15;
      double rounded = round(c * 10.0) / 10.0;
      set_number(info, @"temperature_c", @(rounded));
    }
  }

  if (voltage && amperage) {
    double v = (double)voltage.longLongValue / 1000.0;
    double a = (double)amperage.longLongValue / 1000.0;
    double w = v * a;
    double rounded = round(w * 10.0) / 10.0;
    set_number(info, @"power_w", @(rounded));
  }

  if (raw_max && design && design.longLongValue > 0) {
    double pct = ((double)raw_max.longLongValue / (double)design.longLongValue) * 100.0;
    double rounded = round(pct * 10.0) / 10.0;
    set_number(info, @"health_percent", @(rounded));
  }

  CFRelease(props);
}

int main(int argc, char **argv) {
  @autoreleasepool {
    (void)argc;
    (void)argv;

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    add_power_source_info(info);
    add_smart_battery_info(info);

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


