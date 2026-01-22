/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class RdzWx;

@interface MDNSHandler : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>

@property (nonatomic, weak) RdzWx *plugin;

- (void)initializeWithPlugin:(RdzWx*)plugin;
- (void)start;
- (void)stop;
- (void)updateDiscovery:(NSString*)mode address:(NSString*)address;

@end