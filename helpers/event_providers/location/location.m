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

@interface Locator : NSObject<CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *manager;
@end

@implementation Locator

- (instancetype)init {
  self = [super init];
  if (!self) return nil;
  self.manager = [CLLocationManager new];
  self.manager.delegate = self;
  self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
  return self;
}

// macOS 12+
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
  CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
  fprintf(stderr, "[location] Authorization changed: %s\n", authStatusString(status));
  if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
    gExitCode = 2;
    CFRunLoopStop(CFRunLoopGetCurrent());
  }
}

// macOS 11 and earlier
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
  if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
    gExitCode = 2;
    CFRunLoopStop(CFRunLoopGetCurrent());
  }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
  CLLocation *loc = locations.lastObject;
  if (!loc) return;
  fprintf(stderr, "[location] Acquired location.\n");
  printf("%.6f,%.6f\n", loc.coordinate.latitude, loc.coordinate.longitude);
  fflush(stdout);
  gExitCode = 0;
  CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
  fprintf(stderr, "[location] Failed with error: %s\n", error.localizedDescription.UTF8String);
  if ([error.domain isEqualToString:kCLErrorDomain] && error.code == 1) {
    fprintf(stderr, "[location] Hint: If running from Terminal/iTerm, allow that app in System Settings → Privacy & Security → Location Services.\n");
    gExitCode = 2;
  } else {
    gExitCode = 1;
  }
  CFRunLoopStop(CFRunLoopGetCurrent());
}

@end

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    Locator *locator = [Locator new];

    if (![CLLocationManager locationServicesEnabled]) {
      fprintf(stderr, "[location] Location Services are disabled. Enable in System Settings → Privacy & Security → Location Services.\n");
      return 2;
    }

    fprintf(stderr, "[location] Requesting When-In-Use authorization (first run may prompt)...\n");
    if ([locator.manager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
      [locator.manager requestWhenInUseAuthorization];
    }
    if ([locator.manager respondsToSelector:@selector(requestLocation)]) {
      fprintf(stderr, "[location] Requesting one-shot location and starting updates...\n");
      [locator.manager requestLocation];
    } else {
      fprintf(stderr, "[location] Starting updates...\n");
    }
    [locator.manager startUpdatingLocation];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      fprintf(stderr, "[location] Timed out waiting for location.\n");
      gExitCode = 3;
      CFRunLoopStop(CFRunLoopGetCurrent());
    });

    CFRunLoopRun();
    [locator.manager stopUpdatingLocation];
    return gExitCode;
  }
}


