#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>

void ax_init() {
  const void *keys[] = { kAXTrustedCheckOptionPrompt };
  const void *values[] = { kCFBooleanTrue };

  CFDictionaryRef options;
  options = CFDictionaryCreate(kCFAllocatorDefault,
                               keys,
                               values,
                               sizeof(keys) / sizeof(*keys),
                               &kCFCopyStringDictionaryKeyCallBacks,
                               &kCFTypeDictionaryValueCallBacks     );

  bool trusted = AXIsProcessTrustedWithOptions(options);
  CFRelease(options);
  if (!trusted) exit(1);
}

static bool ax_try_action(AXUIElementRef element, CFStringRef action) {
  return AXUIElementPerformAction(element, action) == kAXErrorSuccess;
}

static bool ax_get_center_point(AXUIElementRef element, CGPoint *out_point) {
  if (!out_point) return false;
  CFTypeRef position_ref = NULL;
  CFTypeRef size_ref = NULL;
  if (AXUIElementCopyAttributeValue(element,
                                    kAXPositionAttribute,
                                    &position_ref) != kAXErrorSuccess || !position_ref) {
    return false;
  }
  if (AXUIElementCopyAttributeValue(element,
                                    kAXSizeAttribute,
                                    &size_ref) != kAXErrorSuccess || !size_ref) {
    CFRelease(position_ref);
    return false;
  }

  CGPoint position = CGPointZero;
  CGSize size = CGSizeZero;
  AXValueGetValue(position_ref, kAXValueCGPointType, &position);
  AXValueGetValue(size_ref, kAXValueCGSizeType, &size);
  CFRelease(position_ref);
  CFRelease(size_ref);

  out_point->x = position.x + (size.width * 0.5);
  out_point->y = position.y + (size.height * 0.5);
  return true;
}

static void ax_click_point(CGPoint point) {
  CGEventRef down = CGEventCreateMouseEvent(NULL,
                                            kCGEventLeftMouseDown,
                                            point,
                                            kCGMouseButtonLeft);
  CGEventRef up = CGEventCreateMouseEvent(NULL,
                                          kCGEventLeftMouseUp,
                                          point,
                                          kCGMouseButtonLeft);
  if (down) {
    CGEventPost(kCGHIDEventTap, down);
    CFRelease(down);
  }
  if (up) {
    CGEventPost(kCGHIDEventTap, up);
    CFRelease(up);
  }
}

void ax_perform_click(AXUIElementRef element) {
  if (!element) return;
  AXUIElementPerformAction(element, kAXCancelAction);
  usleep(150000);
  if (ax_try_action(element, kAXPressAction)) return;
  if (ax_try_action(element, kAXShowMenuAction)) return;

  CGPoint center = CGPointZero;
  if (ax_get_center_point(element, &center)) {
    ax_click_point(center);
  }
}

CFStringRef ax_get_title(AXUIElementRef element) {
  CFTypeRef title = NULL;
  AXError error = AXUIElementCopyAttributeValue(element,
                                                kAXTitleAttribute,
                                                &title            );

  if (error != kAXErrorSuccess) return NULL;
  return title;
}

void ax_select_menu_option(AXUIElementRef app, int id) {
  AXUIElementRef menubars_ref = NULL;
  CFArrayRef children_ref = NULL;

  AXError error = AXUIElementCopyAttributeValue(app,
                                                kAXMenuBarAttribute,
                                                (CFTypeRef*)&menubars_ref);
  if (error == kAXErrorSuccess) {
    error = AXUIElementCopyAttributeValue(menubars_ref,
                                          kAXVisibleChildrenAttribute,
                                          (CFTypeRef*)&children_ref   );

    if (error == kAXErrorSuccess) {
      uint32_t count = CFArrayGetCount(children_ref);
      if (id < count) {
        AXUIElementRef item = CFArrayGetValueAtIndex(children_ref, id);
        ax_perform_click(item);
      }
      if (children_ref) CFRelease(children_ref);
    }
    if (menubars_ref) CFRelease(menubars_ref);
  }
}

void ax_print_menu_options(AXUIElementRef app) {
  AXUIElementRef menubars_ref = NULL;
  CFTypeRef menubar = NULL;
  CFArrayRef children_ref = NULL;

  AXError error = AXUIElementCopyAttributeValue(app,
                                                kAXMenuBarAttribute,
                                                (CFTypeRef*)&menubars_ref);
  if (error == kAXErrorSuccess) {
    error = AXUIElementCopyAttributeValue(menubars_ref,
                                          kAXVisibleChildrenAttribute,
                                          (CFTypeRef*)&children_ref   );

    if (error == kAXErrorSuccess) {
      uint32_t count = CFArrayGetCount(children_ref);

      for (int i = 1; i < count; i++) {
        AXUIElementRef item = CFArrayGetValueAtIndex(children_ref, i);
        CFTypeRef title = ax_get_title(item);

        if (title && CFGetTypeID(title) == CFStringGetTypeID()) {
          // Ensure sufficient buffer for UTF-8 (up to 4 bytes per code unit + NUL)
          CFIndex length = CFStringGetLength((CFStringRef)title);
          CFIndex max_len = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
          char buffer[max_len];
          Boolean ok = CFStringGetCString((CFStringRef)title, buffer, max_len, kCFStringEncodingUTF8);
          if (ok) {
            printf("%s\n", buffer);
          } else {
            // Fallback: use external representation to UTF-8 and write bytes directly
            CFDataRef data = CFStringCreateExternalRepresentation(kCFAllocatorDefault,
                                                                  (CFStringRef)title,
                                                                  kCFStringEncodingUTF8,
                                                                  0);
            if (data) {
              fwrite(CFDataGetBytePtr(data), 1, CFDataGetLength(data), stdout);
              fputc('\n', stdout);
              CFRelease(data);
            }
          }
          CFRelease(title);
        } else {
          printf("•\n");
        }
      }
    }
    if (menubars_ref) CFRelease(menubars_ref);
    if (children_ref) CFRelease(children_ref);
  }
}

static bool remember_value(char seen[][512], int *seen_count, const char *value) {
  if (!value || !*value) return false;
  for (int i = 0; i < *seen_count; i++) {
    if (strcmp(seen[i], value) == 0) return false;
  }
  if (*seen_count >= 256) return false;
  strncpy(seen[*seen_count], value, sizeof(seen[*seen_count]) - 1);
  seen[*seen_count][sizeof(seen[*seen_count]) - 1] = '\0';
  (*seen_count)++;
  return true;
}

void ax_print_menu_extras() {
  char seen[256][512];
  int seen_count = 0;

  ProcessSerialNumber psn = {0, kNoProcess};
  while (GetNextProcess(&psn) == noErr) {
    pid_t pid = 0;
    if (GetProcessPID(&psn, &pid) != noErr || pid <= 0) continue;

    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (!app) continue;

    CFTypeRef extras = NULL;
    if (AXUIElementCopyAttributeValue(app,
                                      kAXExtrasMenuBarAttribute,
                                      &extras) != kAXErrorSuccess || !extras) {
      CFRelease(app);
      continue;
    }

    CFArrayRef children_ref = NULL;
    if (AXUIElementCopyAttributeValue(extras,
                                      kAXVisibleChildrenAttribute,
                                      (CFTypeRef*)&children_ref) != kAXErrorSuccess || !children_ref) {
      CFRelease(extras);
      CFRelease(app);
      continue;
    }

    CFIndex count = CFArrayGetCount(children_ref);
    if (count <= 0) {
      CFRelease(children_ref);
      CFRelease(extras);
      CFRelease(app);
      continue;
    }

    CFStringRef proc_name = NULL;
    if (CopyProcessName(&psn, &proc_name) != noErr || !proc_name) {
      CFRelease(children_ref);
      CFRelease(extras);
      CFRelease(app);
      continue;
    }

    char owner_buffer[256];
    owner_buffer[0] = '\0';
    Boolean ok = CFStringGetCString(proc_name,
                                    owner_buffer,
                                    sizeof(owner_buffer),
                                    kCFStringEncodingUTF8);
    CFRelease(proc_name);
    if (!ok || owner_buffer[0] == '\0') {
      CFRelease(children_ref);
      CFRelease(extras);
      CFRelease(app);
      continue;
    }

    if (remember_value(seen, &seen_count, owner_buffer)) {
      printf("%s\n", owner_buffer);
    }

    char buffer[512];
    for (CFIndex i = 0; i < count; i++) {
      AXUIElementRef item = CFArrayGetValueAtIndex(children_ref, i);
      CFTypeRef title = ax_get_title(item);
      if (!title || CFGetTypeID(title) != CFStringGetTypeID()) {
        if (title) CFRelease(title);
        continue;
      }

      char name_buffer[256];
      name_buffer[0] = '\0';
      if (CFStringGetCString((CFStringRef)title,
                             name_buffer,
                             sizeof(name_buffer),
                             kCFStringEncodingUTF8)) {
        if (name_buffer[0] != '\0') {
          snprintf(buffer, sizeof(buffer), "%s,%s", owner_buffer, name_buffer);
          if (remember_value(seen, &seen_count, buffer)) {
            printf("%s\n", buffer);
          }
        }
      }
      CFRelease(title);
    }

    CFRelease(children_ref);
    CFRelease(extras);
    CFRelease(app);
  }
}

static AXUIElementRef ax_get_extra_item_for_pid(pid_t target_pid, const double *xs, int xs_count, bool owner_only) {
  AXUIElementRef app = AXUIElementCreateApplication(target_pid);
  if (!app) return NULL;

  AXUIElementRef result = NULL;
  CFTypeRef extras = NULL;
  CFArrayRef children_ref = NULL;

  AXError error = AXUIElementCopyAttributeValue(app,
                                                kAXExtrasMenuBarAttribute,
                                                &extras                   );
  if (error == kAXErrorSuccess && extras) {
    error = AXUIElementCopyAttributeValue(extras,
                                          kAXVisibleChildrenAttribute,
                                          (CFTypeRef*)&children_ref   );
    if (error == kAXErrorSuccess && children_ref) {
      uint32_t count = CFArrayGetCount(children_ref);
      if (count > 0) {
        if (!xs || xs_count <= 0) {
          result = (AXUIElementRef)CFRetain(CFArrayGetValueAtIndex(children_ref, 0));
        } else {
          const double threshold = 12.0;
          double best_delta = 1e9;
          AXUIElementRef best = NULL;
          for (uint32_t i = 0; i < count; i++) {
            AXUIElementRef item = CFArrayGetValueAtIndex(children_ref, i);
            CFTypeRef position_ref = NULL;
            if (AXUIElementCopyAttributeValue(item, kAXPositionAttribute, &position_ref) != kAXErrorSuccess || !position_ref) {
              continue;
            }
            CGPoint position = CGPointZero;
            AXValueGetValue(position_ref, kAXValueCGPointType, &position);
            CFRelease(position_ref);

            for (int j = 0; j < xs_count; j++) {
              double delta = fabs(position.x - xs[j]);
              if (delta < best_delta) {
                best_delta = delta;
                best = item;
              }
            }
          }
          if (best && best_delta <= threshold) {
            result = (AXUIElementRef)CFRetain(best);
          } else if (best && owner_only) {
            result = (AXUIElementRef)CFRetain(best);
          }
        }
      }
    }
  }

  if (children_ref) CFRelease(children_ref);
  if (extras) CFRelease(extras);
  CFRelease(app);
  return result;
}

AXUIElementRef ax_get_extra_menu_item(char* alias) {
  if (!alias || !*alias) return NULL;
  bool owner_only = strchr(alias, ',') == NULL;

  pid_t pid = 0;
  double match_x[32];
  int match_x_count = 0;

  CFArrayRef window_list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll,
                                                      kCGNullWindowID        );
  if (!window_list) return NULL;
  char owner_buffer[256];
  char name_buffer[256];
  char buffer[512];
  int window_count = CFArrayGetCount(window_list);
  for (int i = 0; i < window_count; ++i) {
    CFDictionaryRef dictionary = CFArrayGetValueAtIndex(window_list, i);
    if (!dictionary) continue;

    CFStringRef owner_ref = CFDictionaryGetValue(dictionary,
                                                 kCGWindowOwnerName);

    CFNumberRef owner_pid_ref = CFDictionaryGetValue(dictionary,
                                                     kCGWindowOwnerPID);

    CFStringRef name_ref = CFDictionaryGetValue(dictionary, kCGWindowName);
    CFNumberRef layer_ref = CFDictionaryGetValue(dictionary, kCGWindowLayer);
    CFDictionaryRef bounds_ref = CFDictionaryGetValue(dictionary,
                                                      kCGWindowBounds);

    if (!owner_ref || !owner_pid_ref || !layer_ref || !bounds_ref)
      continue;
    if (!owner_only && !name_ref)
      continue;

    long long int layer = 0;
    CFNumberGetValue(layer_ref, CFNumberGetType(layer_ref), &layer);
    uint64_t owner_pid = 0;
    CFNumberGetValue(owner_pid_ref,
                     CFNumberGetType(owner_pid_ref),
                     &owner_pid                     );

    if (layer != 0x19) continue;
    CGRect bounds = CGRectNull;
    if (!CGRectMakeWithDictionaryRepresentation(bounds_ref, &bounds)) continue;
    CFStringGetCString(owner_ref,
                       owner_buffer,
                       sizeof(owner_buffer),
                       kCFStringEncodingUTF8);

    bool match = false;
    if (owner_only) {
      match = strcmp(owner_buffer, alias) == 0;
    } else {
      CFStringGetCString(name_ref,
                         name_buffer,
                         sizeof(name_buffer),
                         kCFStringEncodingUTF8);
      snprintf(buffer, sizeof(buffer), "%s,%s", owner_buffer, name_buffer);
      match = strcmp(buffer, alias) == 0;
    }

    if (match) {
      pid = owner_pid;
      if (match_x_count < (int)(sizeof(match_x) / sizeof(match_x[0]))) {
        match_x[match_x_count++] = bounds.origin.x;
      }
      if (!owner_only) break;
    }
  }
  CFRelease(window_list);

  if (pid) {
    AXUIElementRef item = ax_get_extra_item_for_pid(pid, match_x, match_x_count, owner_only);
    if (item) return item;
    if (owner_only) {
      item = ax_get_extra_item_for_pid(pid, NULL, 0, owner_only);
      if (item) return item;
    }
  }

  if (!owner_only) return NULL;

  // Fallback: resolve PID by app name and click its first extra.
  ProcessSerialNumber psn = {0, kNoProcess};
  while (GetNextProcess(&psn) == noErr) {
    CFStringRef proc_name = NULL;
    if (CopyProcessName(&psn, &proc_name) != noErr || !proc_name) continue;

    char proc_buf[256];
    proc_buf[0] = '\0';
    CFStringGetCString(proc_name, proc_buf, sizeof(proc_buf), kCFStringEncodingUTF8);
    CFRelease(proc_name);
    if (proc_buf[0] == '\0') continue;

    if (strcasecmp(proc_buf, alias) != 0) continue;

    pid_t found = 0;
    if (GetProcessPID(&psn, &found) == noErr && found > 0) {
      AXUIElementRef item = ax_get_extra_item_for_pid(found, NULL, 0, owner_only);
      if (item) return item;
    }
  }

  return NULL;
}

extern int SLSMainConnectionID();
extern void SLSSetMenuBarVisibilityOverrideOnDisplay(int cid, int did, bool enabled);
extern void SLSSetMenuBarVisibilityOverrideOnDisplay(int cid, int did, bool enabled);
extern void SLSSetMenuBarInsetAndAlpha(int cid, double u1, double u2, float alpha);
int ax_select_menu_extra(char* alias) {
  AXUIElementRef item = ax_get_extra_menu_item(alias);
  if (!item) return 2;
  SLSSetMenuBarInsetAndAlpha(SLSMainConnectionID(), 0, 1, 0.0);
  SLSSetMenuBarVisibilityOverrideOnDisplay(SLSMainConnectionID(), 0, true);
  SLSSetMenuBarInsetAndAlpha(SLSMainConnectionID(), 0, 1, 0.0);
  ax_perform_click(item);
  SLSSetMenuBarVisibilityOverrideOnDisplay(SLSMainConnectionID(), 0, false);
  SLSSetMenuBarInsetAndAlpha(SLSMainConnectionID(), 0, 1, 1.0);
  CFRelease(item);
  return 0;
}

extern void _SLPSGetFrontProcess(ProcessSerialNumber* psn);
extern void SLSGetConnectionIDForPSN(int cid, ProcessSerialNumber* psn, int* cid_out);
extern void SLSConnectionGetPID(int cid, pid_t* pid_out);
AXUIElementRef ax_get_front_app() {
  ProcessSerialNumber psn;
  _SLPSGetFrontProcess(&psn);
  int target_cid;
  SLSGetConnectionIDForPSN(SLSMainConnectionID(), &psn, &target_cid);

  pid_t pid;
  SLSConnectionGetPID(target_cid, &pid);
  return AXUIElementCreateApplication(pid);
}

int main (int argc, char **argv) {
  if (argc == 1) {
    printf("Usage: %s [-l | -s id/alias | -x ]\n", argv[0]);
    exit(0);
  }
  ax_init();
  if (strcmp(argv[1], "-l") == 0) {
    AXUIElementRef app = ax_get_front_app();
    if (!app) return 1;
    ax_print_menu_options(app);
    CFRelease(app);
    return 0;
  } else if (strcmp(argv[1], "-x") == 0) {
    ax_print_menu_extras();
    return 0;
  } else if (argc == 3 && strcmp(argv[1], "-s") == 0) {
    int id = 0;
    if (sscanf(argv[2], "%d", &id) == 1) {
      AXUIElementRef app = ax_get_front_app();
      if (!app) return 1;
      ax_select_menu_option(app, id);
      CFRelease(app);
      return 0;
    } else {
      return ax_select_menu_extra(argv[2]);
    }
  }
  return 1;
}
