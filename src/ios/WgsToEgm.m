/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "WgsToEgm.h"

@interface WgsToEgm ()
@property (nonatomic, strong) NSData *geoidData;
@end

@implementation WgsToEgm

- (void)initializeWithPlugin:(RdzWx*)plugin {
    self.plugin = plugin;
    [self loadGeoidData];
}

- (void)loadGeoidData {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *geoidPath = [mainBundle pathForResource:@"WW15MGH" ofType:@"DAC"];
    
    if (geoidPath) {
        self.geoidData = [NSData dataWithContentsOfFile:geoidPath];
        NSLog(@"WgsToEgm: Loaded geoid data file (%lu bytes)", (unsigned long)self.geoidData.length);
    } else {
        NSLog(@"WgsToEgm: Failed to load geoid data file");
    }
}

- (int)readGeoidAtLatitude:(int)lat longitude:(int)lon {
    if (!self.geoidData) {
        return INT_MIN;
    }
    
    NSUInteger pos = ((lat * 1440) + lon) * 2;
    
    if (pos + 1 >= self.geoidData.length) {
        return INT_MIN;
    }
    
    const uint8_t *bytes = (const uint8_t*)self.geoidData.bytes;
    int result = bytes[pos] * 256 + bytes[pos + 1];
    
    if (result > 32767) {
        result -= 65536;
    }
    
    return result;
}

- (float)wgsToEgm:(double)latitude longitude:(double)longitude {
    if (!self.geoidData) {
        return NAN;
    }
    
    double flatitude = (90.0 - latitude) * 4.0;
    double flongitude = (longitude < 0 ? longitude + 360.0 : longitude) * 4.0;
    
    int ilat = (int)flatitude;
    int ilon = (int)flongitude;
    
    flatitude -= ilat;
    flongitude -= ilon;
    
    int g00 = [self readGeoidAtLatitude:ilat longitude:ilon];
    int g10 = [self readGeoidAtLatitude:ilat + 1 longitude:ilon];
    int g01 = [self readGeoidAtLatitude:ilat longitude:ilon + 1];
    int g11 = [self readGeoidAtLatitude:ilat + 1 longitude:ilon + 1];
    
    if (g00 == INT_MIN || g10 == INT_MIN || g01 == INT_MIN || g11 == INT_MIN) {
        return NAN;
    }
    
    // Bilinear interpolation
    double top = g00 * (1.0 - flatitude) + g10 * flatitude;
    double bottom = g01 * (1.0 - flatitude) + g11 * flatitude;
    double result = (top * (1.0 - flongitude) + bottom * flongitude) * 0.01;
    
    return (float)result;
}

@end