// One-shot scanner to snapshot current space apps and trigger a SketchyBar event.
//
// - No yabai required.
// - Uses CoreGraphics to enumerate on-screen windows and SkyLight to get the
//   current space index on the main display.
// - Emits: --add event 'space_snapshot' (idempotent) and then
//          --trigger 'space_snapshot' space='<idx>' apps='App:count|...'

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../sketchybar.h"

// SkyLight (private) symbols — already used elsewhere in this repo
extern int SLSMainConnectionID(void);
extern CFArrayRef SLSCopyManagedDisplaySpaces(int cid);

static int get_current_space_index() {
  int cid = SLSMainConnectionID();
  int index = 1; // fallback
  CFArrayRef displays = SLSCopyManagedDisplaySpaces(cid);
  if (!displays) return index;

  if (CFArrayGetCount(displays) > 0) {
    CFDictionaryRef display_dict = (CFDictionaryRef)CFArrayGetValueAtIndex(displays, 0);
    if (display_dict) {
      CFDictionaryRef current_space = NULL;
      CFArrayRef spaces = NULL;
      CFTypeRef tmp = CFDictionaryGetValue(display_dict, CFSTR("Current Space"));
      if (tmp) current_space = (CFDictionaryRef)tmp;
      tmp = CFDictionaryGetValue(display_dict, CFSTR("Spaces"));
      if (tmp) spaces = (CFArrayRef)tmp;
      if (current_space && spaces) {
        CFStringRef current_uuid = (CFStringRef)CFDictionaryGetValue(current_space, CFSTR("uuid"));
        if (current_uuid) {
          CFIndex count = CFArrayGetCount(spaces);
          for (CFIndex i = 0; i < count; i++) {
            CFDictionaryRef space_dict = (CFDictionaryRef)CFArrayGetValueAtIndex(spaces, i);
            if (!space_dict) continue;
            CFStringRef uuid = (CFStringRef)CFDictionaryGetValue(space_dict, CFSTR("uuid"));
            if (uuid && CFStringCompare(uuid, current_uuid, 0) == kCFCompareEqualTo) {
              index = (int)(i + 1); // 1-based like your config
              break;
            }
          }
        }
      }
    }
  }
  CFRelease(displays);
  return index;
}

static void append_kv_pair(char* buffer, size_t capacity, const char* key, int value, int* first) {
  char entry[512];
  snprintf(entry, sizeof(entry), "%s%s:%d", (*first ? "" : "|"), key, value);
  strncat(buffer, entry, capacity - strlen(buffer) - 1);
  *first = 0;
}

int main(int argc, char** argv) {
  // Build map: appName -> count for on-screen windows (current space)
  CFArrayRef window_list = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly,
      kCGNullWindowID);

  // Prepare map in CFDictionary<String, CFNumber>
  CFMutableDictionaryRef counts = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                            0,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks);

  if (window_list) {
    CFIndex n = CFArrayGetCount(window_list);
    for (CFIndex i = 0; i < n; i++) {
      CFDictionaryRef info = (CFDictionaryRef)CFArrayGetValueAtIndex(window_list, i);
      if (!info) continue;

      // Layer filter: only standard app windows
      CFNumberRef layer_ref = (CFNumberRef)CFDictionaryGetValue(info, kCGWindowLayer);
      int layer = 0;
      if (layer_ref) CFNumberGetValue(layer_ref, kCFNumberIntType, &layer);
      if (layer != 0) continue;

      CFStringRef owner = (CFStringRef)CFDictionaryGetValue(info, kCGWindowOwnerName);
      if (!owner) continue;

      // Count per owner
      CFNumberRef existing = (CFNumberRef)CFDictionaryGetValue(counts, owner);
      int val = 0;
      if (existing) CFNumberGetValue(existing, kCFNumberIntType, &val);
      val += 1;
      CFNumberRef updated = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &val);
      CFDictionarySetValue(counts, owner, updated);
      CFRelease(updated);
    }
    CFRelease(window_list);
  }

  // Serialize: App:count|App2:count
  char apps_buf[8192];
  apps_buf[0] = '\0';
  int first = 1;

  CFIndex dict_count = CFDictionaryGetCount(counts);
  if (dict_count > 0) {
    const void** keys = (const void**)malloc(sizeof(void*) * dict_count);
    const void** values = (const void**)malloc(sizeof(void*) * dict_count);
    CFDictionaryGetKeysAndValues(counts, keys, values);
    for (CFIndex i = 0; i < dict_count; i++) {
      CFStringRef app = (CFStringRef)keys[i];
      CFNumberRef num = (CFNumberRef)values[i];
      int count = 0;
      CFNumberGetValue(num, kCFNumberIntType, &count);

      // Convert CFStringRef -> UTF-8 C string
      CFIndex len = CFStringGetLength(app);
      CFIndex max_len = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
      char* name = (char*)malloc(max_len);
      if (CFStringGetCString(app, name, max_len, kCFStringEncodingUTF8)) {
        append_kv_pair(apps_buf, sizeof(apps_buf), name, count, &first);
      }
      free(name);
    }
    free(keys);
    free(values);
  }

  if (dict_count == 0) {
    // Leave apps_buf empty to indicate no apps
  }

  CFRelease(counts);

  int space_index = get_current_space_index();

  // Announce event and trigger
  char msg[1024];
  snprintf(msg, sizeof(msg), "--add event 'space_snapshot'");
  sketchybar(msg);

  // Quote apps_buf in single quotes; sketchybar.h removes quotes for formatting
  char trigger[10000];
  snprintf(trigger, sizeof(trigger), "--trigger 'space_snapshot' space='%d' apps='%s'",
           space_index, apps_buf);
  sketchybar(trigger);

  return 0;
}


