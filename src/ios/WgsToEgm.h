/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class RdzWx;

@interface WgsToEgm : NSObject

@property (nonatomic, weak) RdzWx *plugin;

- (void)initializeWithPlugin:(RdzWx*)plugin;
- (float)wgsToEgm:(double)latitude longitude:(double)longitude;

@end