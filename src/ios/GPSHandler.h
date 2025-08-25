/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@class RdzWx;

@interface GPSHandler : NSObject <CLLocationManagerDelegate>

@property (nonatomic, weak) RdzWx *plugin;
@property (nonatomic, strong) CLLocationManager *locationManager;

- (void)initializeWithPlugin:(RdzWx*)plugin;
- (void)start;
- (void)stop;

@end