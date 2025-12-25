// Fast Spaces count helper.
//
// - Uses SkyLight managed display spaces to count the number of Spaces.
// - Prints a single integer (max spaces across displays), capped to 10.
// - Intended for one-shot use at startup so the Lua config can create only the
//   required number of `space` items (avoids 10->N flash).

#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

#include "../sketchybar.h"

// SkyLight (private)
extern int SLSMainConnectionID(void);
extern CFArrayRef SLSCopyManagedDisplaySpaces(int cid);

static int spaces_count_for_display(CFDictionaryRef display_dict) {
  if (!display_dict) return 0;
  CFTypeRef tmp = CFDictionaryGetValue(display_dict, CFSTR("Spaces"));
  if (!tmp || CFGetTypeID(tmp) != CFArrayGetTypeID()) return 0;
  return (int)CFArrayGetCount((CFArrayRef)tmp);
}

int main(int argc, char** argv) {
  (void)argc;
  (void)argv;

  int cid = SLSMainConnectionID();
  CFArrayRef displays = SLSCopyManagedDisplaySpaces(cid);

  int max_spaces = 0;
  if (displays && CFGetTypeID(displays) == CFArrayGetTypeID()) {
    CFIndex n = CFArrayGetCount(displays);
    for (CFIndex i = 0; i < n; i++) {
      CFDictionaryRef display_dict = (CFDictionaryRef)CFArrayGetValueAtIndex(displays, i);
      int count = spaces_count_for_display(display_dict);
      if (count > max_spaces) max_spaces = count;
    }
  }

  if (displays) CFRelease(displays);

  if (max_spaces <= 0) max_spaces = 10;
  if (max_spaces > 10) max_spaces = 10;

  printf("%d\n", max_spaces);
  return 0;
}


