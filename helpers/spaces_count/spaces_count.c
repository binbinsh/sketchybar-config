// Fast Spaces count helper.
//
// - Uses SkyLight managed display spaces to count the number of Spaces.
// - Prints two integers: "<max_spaces> <display_count>".
// - Intended for one-shot use at startup so the Lua config can create only the
//   required number of `space` items (avoids 10->N flash and extra per-display items).

#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

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
  int display_count = 1;
  if (displays && CFGetTypeID(displays) == CFArrayGetTypeID()) {
    CFIndex n = CFArrayGetCount(displays);
    if (n > 0) display_count = (int)n;
    for (CFIndex i = 0; i < n; i++) {
      CFDictionaryRef display_dict = (CFDictionaryRef)CFArrayGetValueAtIndex(displays, i);
      int count = spaces_count_for_display(display_dict);
      if (count > max_spaces) max_spaces = count;
    }
  }

  if (displays) CFRelease(displays);

  if (max_spaces <= 0) max_spaces = 10;
  if (max_spaces > 10) max_spaces = 10;
  if (display_count <= 0) display_count = 1;

  printf("%d %d\n", max_spaces, display_count);
  return 0;
}
