// Return current space index + display index under the mouse cursor.
//
// Output (JSON): {"space":<1-based>, "display":<0-based>}
//
// - Space index is derived from SkyLight's managed display spaces.
// - Display index is the index in SkyLight's display list (0 = main display).
// - Intended to pin SketchyBar popups to the space/display where they were opened.
//
// NOTE: Uses private SkyLight APIs (like other helpers in this repo).

#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#include "../sketchybar.h"

// SkyLight (private)
extern int SLSMainConnectionID(void);
extern CFArrayRef SLSCopyManagedDisplaySpaces(int cid);

static CGPoint mouse_location_global(void) {
  CGPoint p = CGPointMake(0, 0);
  CGEventRef event = CGEventCreate(NULL);
  if (event) {
    p = CGEventGetLocation(event);
    CFRelease(event);
  }
  return p;
}

static CGDirectDisplayID display_under_point(CGPoint p) {
  uint32_t count = 0;
  if (CGGetActiveDisplayList(0, NULL, &count) != kCGErrorSuccess || count == 0) {
    return CGMainDisplayID();
  }

  CGDirectDisplayID* displays = (CGDirectDisplayID*)calloc(count, sizeof(CGDirectDisplayID));
  if (!displays) return CGMainDisplayID();

  if (CGGetActiveDisplayList(count, displays, &count) != kCGErrorSuccess || count == 0) {
    free(displays);
    return CGMainDisplayID();
  }

  CGDirectDisplayID chosen = CGMainDisplayID();
  for (uint32_t i = 0; i < count; i++) {
    CGRect bounds = CGDisplayBounds(displays[i]);
    if (CGRectContainsPoint(bounds, p)) {
      chosen = displays[i];
      break;
    }
  }

  free(displays);
  return chosen;
}

static bool cfstring_matches_display(CFStringRef s, CGDirectDisplayID did, CFStringRef did_uuid_str) {
  if (!s) return false;
  if (did_uuid_str && CFStringCompare(s, did_uuid_str, 0) == kCFCompareEqualTo) {
    return true;
  }
  // Some versions expose a decimal display id as string.
  long long n = CFStringGetIntValue(s);
  if (n > 0 && (CGDirectDisplayID)n == did) {
    return true;
  }
  return false;
}

static bool value_matches_display(CFTypeRef v,
                                  CGDirectDisplayID did,
                                  CFUUIDRef did_uuid,
                                  CFStringRef did_uuid_str) {
  if (!v) return false;
  CFTypeID tid = CFGetTypeID(v);

  if (tid == CFStringGetTypeID()) {
    return cfstring_matches_display((CFStringRef)v, did, did_uuid_str);
  }
  if (tid == CFNumberGetTypeID()) {
    long long n = 0;
    if (CFNumberGetValue((CFNumberRef)v, kCFNumberSInt64Type, &n)) {
      return (CGDirectDisplayID)n == did;
    }
    return false;
  }
  if (did_uuid && tid == CFUUIDGetTypeID()) {
    return CFEqual(v, did_uuid);
  }
  if (did_uuid && tid == CFDataGetTypeID()) {
    CFDataRef data = (CFDataRef)v;
    if (CFDataGetLength(data) == 16) {
      CFUUIDBytes bytes;
      const UInt8* b = CFDataGetBytePtr(data);
      for (int i = 0; i < 16; i++) ((UInt8*)&bytes)[i] = b[i];
      CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, bytes);
      bool ok = uuid && CFEqual(uuid, did_uuid);
      if (uuid) CFRelease(uuid);
      return ok;
    }
  }

  return false;
}

static bool display_dict_matches(CFDictionaryRef display_dict,
                                 CGDirectDisplayID did,
                                 CFUUIDRef did_uuid,
                                 CFStringRef did_uuid_str) {
  if (!display_dict) return false;

  const CFStringRef keys[] = {
    CFSTR("Display Identifier"),
    CFSTR("DisplayIdentifier"),
    CFSTR("Display UUID"),
    CFSTR("DisplayUUID"),
    CFSTR("Display ID"),
    CFSTR("DisplayID"),
  };

  for (size_t i = 0; i < (sizeof(keys) / sizeof(keys[0])); i++) {
    CFTypeRef v = CFDictionaryGetValue(display_dict, keys[i]);
    if (value_matches_display(v, did, did_uuid, did_uuid_str)) {
      return true;
    }
  }

  return false;
}

static int current_space_index_for_display(CFDictionaryRef display_dict) {
  int index = 1; // fallback (1-based)
  if (!display_dict) return index;

  CFDictionaryRef current_space = NULL;
  CFArrayRef spaces = NULL;

  CFTypeRef tmp = CFDictionaryGetValue(display_dict, CFSTR("Current Space"));
  if (tmp && CFGetTypeID(tmp) == CFDictionaryGetTypeID()) {
    current_space = (CFDictionaryRef)tmp;
  }

  tmp = CFDictionaryGetValue(display_dict, CFSTR("Spaces"));
  if (tmp && CFGetTypeID(tmp) == CFArrayGetTypeID()) {
    spaces = (CFArrayRef)tmp;
  }

  if (!current_space || !spaces) return index;

  CFTypeRef cu = CFDictionaryGetValue(current_space, CFSTR("uuid"));
  if (!cu || CFGetTypeID(cu) != CFStringGetTypeID()) return index;
  CFStringRef current_uuid = (CFStringRef)cu;

  CFIndex count = CFArrayGetCount(spaces);
  for (CFIndex i = 0; i < count; i++) {
    CFDictionaryRef space_dict = (CFDictionaryRef)CFArrayGetValueAtIndex(spaces, i);
    if (!space_dict) continue;
    CFTypeRef su = CFDictionaryGetValue(space_dict, CFSTR("uuid"));
    if (!su || CFGetTypeID(su) != CFStringGetTypeID()) continue;
    CFStringRef uuid = (CFStringRef)su;
    if (CFStringCompare(uuid, current_uuid, 0) == kCFCompareEqualTo) {
      index = (int)(i + 1);
      break;
    }
  }

  return index;
}

int main(int argc, char** argv) {
  (void)argc;
  (void)argv;

  // Determine display under mouse cursor (CG).
  CGPoint mouse = mouse_location_global();
  CGDirectDisplayID did = display_under_point(mouse);
  CFUUIDRef did_uuid = CGDisplayCreateUUIDFromDisplayID(did);
  CFStringRef did_uuid_str = NULL;
  if (did_uuid) {
    did_uuid_str = CFUUIDCreateString(kCFAllocatorDefault, did_uuid);
  }

  // Query SkyLight managed display spaces.
  int cid = SLSMainConnectionID();
  CFArrayRef displays = SLSCopyManagedDisplaySpaces(cid);

  int display_index = 0; // 0-based
  int space_index = 1;   // 1-based

  if (displays && CFGetTypeID(displays) == CFArrayGetTypeID()) {
    CFIndex n = CFArrayGetCount(displays);
    CFDictionaryRef match_dict = NULL;

    if (n > 0) {
      for (CFIndex i = 0; i < n; i++) {
        CFDictionaryRef display_dict = (CFDictionaryRef)CFArrayGetValueAtIndex(displays, i);
        if (!display_dict) continue;
        if (display_dict_matches(display_dict, did, did_uuid, did_uuid_str)) {
          match_dict = display_dict;
          display_index = (int)i;
          break;
        }
      }
    }

    if (!match_dict && n > 0) {
      match_dict = (CFDictionaryRef)CFArrayGetValueAtIndex(displays, 0);
      display_index = 0;
    }

    if (match_dict) {
      space_index = current_space_index_for_display(match_dict);
    }
  }

  if (displays) CFRelease(displays);
  if (did_uuid_str) CFRelease(did_uuid_str);
  if (did_uuid) CFRelease(did_uuid);

  // JSON output for sbar.exec() (Lua) to parse.
  printf("{\"space\":%d,\"display\":%d}\n", space_index, display_index);
  return 0;
}


