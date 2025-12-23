#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "../sketchybar.h"

static NSString* sanitize(NSString *s) {
  if (!s) return @"";
  NSString *r = [s stringByReplacingOccurrencesOfString:@"'" withString:@" "];
  r = [r stringByReplacingOccurrencesOfString:@"\"" withString:@" "];
  r = [r stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
  r = [r stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
  return r;
}

// Escape a JavaScript snippet so it can be embedded inside an AppleScript string literal
static NSString* escapeForAppleScript(NSString *s) {
  if (!s) return @"";
  NSString *r = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
  r = [r stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  r = [r stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
  return r;
}

// Native Messaging helpers (Chrome/Brave extension → this helper)
static NSDictionary* read_native_msg(void) {
  uint32_t length = 0;
  if (fread(&length, sizeof(length), 1, stdin) != 1) return nil;
  if (length == 0 || length > (50 * 1024)) return nil;
  uint8_t *buffer = malloc(length + 1);
  if (!buffer) return nil;
  size_t readc = fread(buffer, 1, length, stdin);
  buffer[readc] = 0;
  NSData *data = [NSData dataWithBytesNoCopy:buffer length:readc freeWhenDone:YES];
  NSError *err = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
  if (err || ![json isKindOfClass:[NSDictionary class]]) return nil;
  return (NSDictionary *)json;
}

static void write_native_msg(NSDictionary *json) {
  NSError *err = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:&err];
  if (err || !data) return;
  uint32_t length = (uint32_t)data.length;
  fwrite(&length, sizeof(length), 1, stdout);
  fwrite(data.bytes, 1, data.length, stdout);
  fflush(stdout);
}

static void trigger_from_native_payload(NSDictionary *payload, NSString *eventName) {
  static dispatch_once_t once; dispatch_once(&once, ^{ sketchybar("--add event 'media_nowplaying'"); });
  NSString *title = sanitize([[payload objectForKey:@"title"] description]);
  NSString *artist = sanitize([[payload objectForKey:@"artist"] description]);
  NSString *album = sanitize([[payload objectForKey:@"album"] description]);
  NSString *state = [[[payload objectForKey:@"state"] description] lowercaseString];
  if (![state isEqualToString:@"playing"]) state = @"paused";
  NSString *app = sanitize(([[payload objectForKey:@"app"] description] ?: @"YouTube Music"));
  double elapsed = [[[payload objectForKey:@"elapsed"] description] doubleValue];
  double duration = [[[payload objectForKey:@"duration"] description] doubleValue];

  char msg[4096];
  snprintf(msg, sizeof(msg),
           "--trigger '%s' title='%s' artist='%s' album='%s' state='%s' app='%s' elapsed='%.0f' duration='%.0f'",
           eventName.UTF8String,
           title.UTF8String,
           artist.UTF8String,
           album.UTF8String,
           state.UTF8String,
           app.UTF8String,
           elapsed,
           duration);
  sketchybar(msg);
}

// Official API path: transform NSDistributedNotificationCenter playerInfo into our event
static void triggerFromUserInfo(NSDictionary *userInfo, NSString *eventName, NSString *appName) {
  if (!userInfo) return;
  id stateVal = userInfo[@"Player State"] ?: userInfo[@"state"] ?: userInfo[@"State"];
  NSString *state = stateVal ? [[stateVal description] lowercaseString] : @"paused";
  if ([state isEqualToString:@"playing"]) state = @"playing"; else state = @"paused";

  NSString *title = (userInfo[@"Name"] ?: userInfo[@"name"] ?: userInfo[@"Title"] ?: userInfo[@"title"] ?: @"");
  NSString *artist = (userInfo[@"Artist"] ?: userInfo[@"artist"] ?: @"");
  NSString *album = (userInfo[@"Album"] ?: userInfo[@"album"] ?: @"");
  double duration = 0.0; id dur = userInfo[@"Total Time"] ?: userInfo[@"duration"]; if ([dur respondsToSelector:@selector(doubleValue)]) duration = [dur doubleValue];
  double elapsed = 0.0; id el = userInfo[@"Elapsed Time"] ?: userInfo[@"elapsed"]; if ([el respondsToSelector:@selector(doubleValue)]) elapsed = [el doubleValue];

  static dispatch_once_t once; dispatch_once(&once, ^{ sketchybar("--add event 'media_nowplaying'"); });

  char msg[4096];
  snprintf(msg, sizeof(msg),
           "--trigger '%s' title='%s' artist='%s' album='%s' state='%s' app='%s' elapsed='%.0f' duration='%.0f'",
           eventName.UTF8String,
           sanitize([title description]).UTF8String,
           sanitize([artist description]).UTF8String,
           sanitize([album description]).UTF8String,
           state.UTF8String,
           sanitize(appName).UTF8String,
           elapsed,
           duration);
  sketchybar(msg);
}

static void pollLoop(NSString *eventName) {
  NSDistributedNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
  void (^musicHandler)(NSNotification*) = ^(NSNotification *note){ triggerFromUserInfo(note.userInfo, eventName, @"Music"); };
  [dnc addObserverForName:@"com.apple.iTunes.playerInfo" object:nil queue:[NSOperationQueue mainQueue] usingBlock:musicHandler];
  [dnc addObserverForName:@"com.apple.Music.playerInfo" object:nil queue:[NSOperationQueue mainQueue] usingBlock:musicHandler];
  void (^spotifyHandler)(NSNotification*) = ^(NSNotification *note){ triggerFromUserInfo(note.userInfo, eventName, @"Spotify"); };
  [dnc addObserverForName:@"com.spotify.client.PlaybackStateChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:spotifyHandler];

  // Also act as a Native Messaging host when launched by Chrome/Brave extension.
  // We multiplex: if stdin has data (native messaging), read and emit events; otherwise, just run the runloop for DNC.
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
    while (1) {
      @autoreleasepool {
        NSDictionary *msg = read_native_msg();
        if (!msg) break;
        NSString *type = [[msg objectForKey:@"type"] description];
        if ([type isEqualToString:@"nowplaying"]) {
          trigger_from_native_payload(msg, eventName);
          write_native_msg(@{ @"ok": @YES });
        } else if ([type isEqualToString:@"control"]) {
          // Optional: could dispatch AppleScript for Music, or send back ack only
          write_native_msg(@{ @"ok": @YES });
        } else {
          write_native_msg(@{ @"ok": @NO });
        }
      }
    }
  });

  [[NSRunLoop currentRunLoop] run];
}

static void sendCommandName(NSString *name) {
  // First try to control YouTube Music in Chrome/Brave by injecting JS into a matching tab
  NSString *js = nil;
  if ([name isEqualToString:@"toggle"] || [name isEqualToString:@"playpause"]) {
    js = @"(function(){var a=document.querySelector('audio, video');if(a){if(a.paused)a.play();else a.pause();return true;}var sels=['ytmusic-player-bar #play-pause-button','ytmusic-player-bar .play-pause-button','#play-pause-button','.play-pause-button'];for(var i=0;i<sels.length;i++){var el=document.querySelector(sels[i]);if(el){el.click();return true;}}return false;})();";
  } else if ([name isEqualToString:@"next"]) {
    js = @"(function(){var sels=['ytmusic-player-bar #next-button','ytmusic-player-bar .next-button','#next-button','.next-button','tp-yt-paper-icon-button.next-button'];for(var i=0;i<sels.length;i++){var el=document.querySelector(sels[i]);if(el){el.click();return true;}}return false;})();";
  } else if ([name isEqualToString:@"previous"]) {
    js = @"(function(){var sels=['ytmusic-player-bar #previous-button','ytmusic-player-bar .previous-button','#previous-button','.previous-button','tp-yt-paper-icon-button.previous-button'];for(var i=0;i<sels.length;i++){var el=document.querySelector(sels[i]);if(el){el.click();return true;}}return false;})();";
  }

  if (js) {
    NSString *esc = escapeForAppleScript(js);
    NSMutableString *script = [NSMutableString new];
    [script appendString:@"tell application \"System Events\"\n"];
    [script appendString:@"set hasChrome to (exists process \"Google Chrome\")\n"];
    [script appendString:@"set hasBrave to (exists process \"Brave Browser\")\n"];
    [script appendString:@"end tell\n"];
    // Google Chrome
    [script appendString:@"if hasChrome then\n"];
    [script appendString:@"  tell application \"Google Chrome\"\n"];
    [script appendString:@"    repeat with w in windows\n"];
    [script appendString:@"      repeat with t in tabs of w\n"];
    [script appendString:@"        if (URL of t starts with \"https://music.youtube.com\") then\n"];
    [script appendFormat:@"          tell t to execute javascript \"%@\"\n", esc];
    [script appendString:@"          return\n"];
    [script appendString:@"        end if\n"];
    [script appendString:@"      end repeat\n"];
    [script appendString:@"    end repeat\n"];
    [script appendString:@"  end tell\n"];
    [script appendString:@"end if\n"];
    // Brave Browser
    [script appendString:@"if hasBrave then\n"];
    [script appendString:@"  tell application \"Brave Browser\"\n"];
    [script appendString:@"    repeat with w in windows\n"];
    [script appendString:@"      repeat with t in tabs of w\n"];
    [script appendString:@"        if (URL of t starts with \"https://music.youtube.com\") then\n"];
    [script appendFormat:@"          tell t to execute javascript \"%@\"\n", esc];
    [script appendString:@"          return\n"];
    [script appendString:@"        end if\n"];
    [script appendString:@"      end repeat\n"];
    [script appendString:@"    end repeat\n"];
    [script appendString:@"  end tell\n"];
    [script appendString:@"end if\n"];

    NSAppleScript *asYTM = [[NSAppleScript alloc] initWithSource:script];
    [asYTM executeAndReturnError:nil];
  }

  // Fallback to controlling Apple Music
  NSString *cmd = nil;
  if ([name isEqualToString:@"toggle"] || [name isEqualToString:@"playpause"]) {
    cmd = @"tell application \"Music\" to playpause";
  } else if ([name isEqualToString:@"next"]) {
    cmd = @"tell application \"Music\" to next track";
  } else if ([name isEqualToString:@"previous"]) {
    cmd = @"tell application \"Music\" to previous track";
  }
  if (cmd) {
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:cmd];
    [as executeAndReturnError:nil];
  }
}

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    // Control mode: now_playing <command>
    if (argc == 2) {
      NSString *arg = [NSString stringWithUTF8String:argv[1]];
      if ([arg isEqualToString:@"previous"] || [arg isEqualToString:@"next"] ||
          [arg isEqualToString:@"toggle"] || [arg isEqualToString:@"playpause"]) {
        sendCommandName(arg);
        return 0;
      }
    }

    // If launched as Native Messaging host (stdin is a pipe), run pure bridge loop
    if (!isatty(STDIN_FILENO)) {
      while (1) {
        @autoreleasepool {
          NSDictionary *msg = read_native_msg();
          if (!msg) break; // browser closed
          NSString *type = [[msg objectForKey:@"type"] description];
          if ([type isEqualToString:@"nowplaying"]) {
            trigger_from_native_payload(msg, @"media_nowplaying");
            write_native_msg(@{ @"ok": @YES });
          } else if ([type isEqualToString:@"control"]) {
            write_native_msg(@{ @"ok": @YES });
          } else {
            write_native_msg(@{ @"ok": @NO });
          }
        }
      }
      return 0;
    }

    // Provider mode (no native messaging): now_playing <event-name>
    NSString *eventName = @"media_nowplaying";
    if (argc >= 2) {
      eventName = [NSString stringWithUTF8String:argv[1]];
    }
    pollLoop(eventName);
    return 0;
  }
}


