#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

static int gExitCode = 3; // 0=ok, 1=error, 2=denied, 3=timeout

static const char* authStatusString(CLAuthorizationStatus status) {
  switch (status) {
    case kCLAuthorizationStatusNotDetermined: return "NotDetermined";
    case kCLAuthorizationStatusRestricted:    return "Restricted";
    case kCLAuthorizationStatusDenied:        return "Denied";
    default:                                  return "Authorized";
  }
}

@interface AppLocator : NSObject<CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *manager;
@property (atomic, assign) BOOL hasStartedRequests;
- (void)startRequestsIfAuthorized;
@end

@implementation AppLocator

- (instancetype)init {
  self = [super init];
  if (!self) return nil;
  self.manager = [CLLocationManager new];
  self.manager.delegate = self;
  self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
  self.hasStartedRequests = NO;
  return self;
}

- (void)startRequestsIfAuthorized {
  if (self.hasStartedRequests) return;
  CLAuthorizationStatus status = [self.manager authorizationStatus];
  if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
    gExitCode = 2;
    CFRunLoopStop(CFRunLoopGetCurrent());
    return;
  }

#ifdef kCLAuthorizationStatusAuthorizedWhenInUse
  BOOL isAuthorized = (status == kCLAuthorizationStatusAuthorizedAlways ||
                       status == kCLAuthorizationStatusAuthorizedWhenInUse ||
                       status == kCLAuthorizationStatusAuthorized);
#else
  BOOL isAuthorized = (status == kCLAuthorizationStatusAuthorized);
#endif
  if (!isAuthorized) return;

  self.hasStartedRequests = YES;
  if ([self.manager respondsToSelector:@selector(requestLocation)]) {
    fprintf(stderr, "[SketchyBarLocationHelper] Requesting one-shot location and starting updates...\n");
    [self.manager requestLocation];
  } else {
    fprintf(stderr, "[SketchyBarLocationHelper] Starting updates...\n");
  }
  [self.manager startUpdatingLocation];
}

// macOS 12+
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
  CLAuthorizationStatus status = [self.manager authorizationStatus];
  fprintf(stderr, "[SketchyBarLocationHelper] Authorization changed: %s\n", authStatusString(status));
  if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
    gExitCode = 2;
    CFRunLoopStop(CFRunLoopGetCurrent());
    return;
  }
  [self startRequestsIfAuthorized];
}

// macOS 11 and earlier
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
  if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
    gExitCode = 2;
    CFRunLoopStop(CFRunLoopGetCurrent());
    return;
  }
  [self startRequestsIfAuthorized];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
  CLLocation *loc = locations.lastObject;
  if (!loc) return;
  fprintf(stderr, "[SketchyBarLocationHelper] Acquired location.\n");
  // Write to cache file so the widget can read it after open -W returns
  NSString *home = NSHomeDirectory();
  NSString *cacheDir = [home stringByAppendingPathComponent:@".cache/sketchybar"];
  [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *locPath = [cacheDir stringByAppendingPathComponent:@"location.txt"];
  // Maintain same format the widget expects: ts|lat|lon|label
  NSTimeInterval ts = [[NSDate date] timeIntervalSince1970];
  NSString *line = [NSString stringWithFormat:@"%.0f|%f|%f|\n", ts, loc.coordinate.latitude, loc.coordinate.longitude];
  [line writeToFile:locPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
  gExitCode = 0;
  CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
  fprintf(stderr, "[SketchyBarLocationHelper] Failed with error: %s\n", error.localizedDescription.UTF8String);
  if ([error.domain isEqualToString:kCLErrorDomain] && error.code == 1) {
    fprintf(stderr, "[SketchyBarLocationHelper] Hint: Enable this app in System Settings → Privacy & Security → Location Services (it appears as ‘SketchyBar Location Helper’).\n");
    gExitCode = 2;
  } else {
    gExitCode = 1;
  }
  CFRunLoopStop(CFRunLoopGetCurrent());
}

@end

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    AppLocator *locator = [AppLocator new];

    if (![CLLocationManager locationServicesEnabled]) {
      fprintf(stderr, "[SketchyBarLocationHelper] Location Services are disabled. Enable in System Settings → Privacy & Security → Location Services.\n");
      return 2;
    }

    fprintf(stderr, "[SketchyBarLocationHelper] Requesting When-In-Use authorization (first run may prompt)...\n");
    if ([locator.manager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
      [locator.manager requestWhenInUseAuthorization];
    }
    [locator startRequestsIfAuthorized];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      fprintf(stderr, "[SketchyBarLocationHelper] Timed out waiting for location.\n");
      gExitCode = 3;
      CFRunLoopStop(CFRunLoopGetCurrent());
    });

    CFRunLoopRun();
    [locator.manager stopUpdatingLocation];
    return gExitCode;
  }
}


