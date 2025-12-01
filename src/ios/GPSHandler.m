/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "GPSHandler.h"
#import "RdzWx.h"

@implementation GPSHandler

- (void)initializeWithPlugin:(RdzWx*)plugin {
    self.plugin = plugin;
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 0; // Update on any movement
}

- (void)start {
    NSLog(@"GPSHandler: start() called");
    [self requestLocationPermissions];
}

- (void)stop {
    [self.locationManager stopUpdatingLocation];
    NSLog(@"GPSHandler: Stopped location updates");
}

- (void)requestLocationPermissions {
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }

    NSLog(@"GPSHandler: Current authorization status: %d", (int)status);

    switch (status) {
        case kCLAuthorizationStatusNotDetermined:
            NSLog(@"GPSHandler: Requesting location permission...");
            [self.locationManager requestWhenInUseAuthorization];
            break;

        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            NSLog(@"GPSHandler: Location access denied or restricted - cannot start");
            break;

        case kCLAuthorizationStatusAuthorizedWhenInUse:
        case kCLAuthorizationStatusAuthorizedAlways:
            NSLog(@"GPSHandler: Already authorized, starting location updates");
            [self startLocationUpdates];
            break;
    }
}

- (void)startLocationUpdates {
    if ([CLLocationManager locationServicesEnabled]) {
        [self.locationManager startUpdatingLocation];
        NSLog(@"GPSHandler: Started location updates");
    } else {
        NSLog(@"GPSHandler: Location services not enabled");
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = [locations lastObject];
    
    if (location) {
        double latitude = location.coordinate.latitude;
        double longitude = location.coordinate.longitude;
        double altitude = location.altitude;
        float bearing = location.course >= 0 ? (float)location.course : 0.0f;
        float accuracy = (float)location.horizontalAccuracy;
        
        NSLog(@"GPSHandler: Location update: %f, %f", latitude, longitude);
        
        [self.plugin updateGps:latitude 
                     longitude:longitude 
                      altitude:altitude 
                       bearing:bearing 
                      accuracy:accuracy];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"GPSHandler: Location error: %@", error.localizedDescription);
}

// iOS 14+ delegate method (preferred)
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = manager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }

    NSLog(@"GPSHandler: Authorization status changed to: %d", (int)status);

    switch (status) {
        case kCLAuthorizationStatusAuthorizedWhenInUse:
        case kCLAuthorizationStatusAuthorizedAlways:
            NSLog(@"GPSHandler: Location authorization granted");
            [self startLocationUpdates];
            break;

        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            NSLog(@"GPSHandler: Location authorization denied or restricted");
            break;

        case kCLAuthorizationStatusNotDetermined:
            NSLog(@"GPSHandler: Location authorization not yet determined");
            break;
    }
}

// Legacy iOS 13 and earlier delegate method (for backward compatibility)
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    NSLog(@"GPSHandler: Legacy authorization delegate called (iOS 13-)");
    [self locationManagerDidChangeAuthorization:manager];
}

@end