/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class RdzWx;

@interface OfflineTileCache : NSObject

@property (nonatomic, weak) RdzWx *plugin;

- (void)initializeWithPlugin:(RdzWx*)plugin;
- (NSString*)getTileAtX:(int)x y:(int)y z:(int)z;

@end