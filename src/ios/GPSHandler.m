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
    [self requestLocationPermissions];
}

- (void)stop {
    [self.locationManager stopUpdatingLocation];
    NSLog(@"GPSHandler: Stopped location updates");
}

- (void)requestLocationPermissions {
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    
    switch (status) {
        case kCLAuthorizationStatusNotDetermined:
            [self.locationManager requestWhenInUseAuthorization];
            break;
            
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            NSLog(@"GPSHandler: Location access denied");
            break;
            
        case kCLAuthorizationStatusAuthorizedWhenInUse:
        case kCLAuthorizationStatusAuthorizedAlways:
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

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    switch (status) {
        case kCLAuthorizationStatusAuthorizedWhenInUse:
        case kCLAuthorizationStatusAuthorizedAlways:
            [self startLocationUpdates];
            break;
            
        case kCLAuthorizationStatusDenied:
        case kCLAuthorizationStatusRestricted:
            NSLog(@"GPSHandler: Location authorization denied");
            break;
            
        case kCLAuthorizationStatusNotDetermined:
            break;
    }
}

@end