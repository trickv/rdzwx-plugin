/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>

@class RdzWx;

@interface JsonRdzHandler : NSObject

@property (nonatomic, weak) RdzWx *plugin;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL active;

- (void)initializeWithPlugin:(RdzWx*)plugin;
- (void)start;
- (void)stop;
- (void)connectToHost:(NSString*)host port:(int)port;
- (void)closeConnection;
- (void)postGpsPosition:(double)latitude longitude:(double)longitude altitude:(double)altitude bearing:(float)bearing accuracy:(float)accuracy;
- (void)postAlive;

@end