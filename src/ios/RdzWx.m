/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "RdzWx.h"
#import "JsonRdzHandler.h"
#import "GPSHandler.h"
#import "MDNSHandler.h"
#import "WgsToEgm.h"
#import "OfflineTileCache.h"
#import <Cordova/CDVPluginResult.h>

@implementation RdzWx

- (void)pluginInitialize {
    [super pluginInitialize];
    
    self.running = NO;
    self.jsonrdzHandler = [[JsonRdzHandler alloc] init];
    self.gpsHandler = [[GPSHandler alloc] init];
    self.mdnsHandler = [[MDNSHandler alloc] init];
    self.wgsToEgm = [[WgsToEgm alloc] init];
    self.offlineTileCache = [[OfflineTileCache alloc] init];
    
    // Initialize handlers with reference to this plugin
    [self.jsonrdzHandler initializeWithPlugin:self];
    [self.gpsHandler initializeWithPlugin:self];
    [self.mdnsHandler initializeWithPlugin:self];
    [self.wgsToEgm initializeWithPlugin:self];
    [self.offlineTileCache initializeWithPlugin:self];
    
    NSLog(@"RdzWx plugin initialized");
}

- (void)start:(CDVInvokedUrlCommand*)command {
    NSLog(@"RdzWx start called");
    
    if (self.running) {
        NSLog(@"Plugin already running");
        return;
    }
    
    self.callbackId = command.callbackId;
    self.running = YES;
    
    [self.gpsHandler start];
    [self.mdnsHandler start];
    [self.jsonrdzHandler start];
    
    // Start periodic status updates
    [self scheduleStatusUpdate];
    
    // Send initial status
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                            messageAsString:@"{ \"msgtype\": \"pluginstatus\", \"status\": \"OK\"}"];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
}

- (void)stop:(CDVInvokedUrlCommand*)command {
    NSLog(@"RdzWx stop called");
    
    if (!self.running) {
        NSLog(@"Plugin already stopped");
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
        return;
    }
    
    [self.jsonrdzHandler stop];
    [self.gpsHandler stop];
    [self.mdnsHandler stop];
    
    self.running = NO;
    self.callbackId = nil;
    
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)closeconn:(CDVInvokedUrlCommand*)command {
    [self.jsonrdzHandler closeConnection];
    
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)showmap:(CDVInvokedUrlCommand*)command {
    NSString* mapUrl = [command.arguments objectAtIndex:0];
    
    NSURL* url = [NSURL URLWithString:mapUrl];
    if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
    
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)wgstoegm:(CDVInvokedUrlCommand*)command {
    double lat = [[command.arguments objectAtIndex:0] doubleValue];
    double lon = [[command.arguments objectAtIndex:1] doubleValue];
    
    float egmDiff = [self.wgsToEgm wgsToEgm:lat longitude:lon];
    int result = (int)(egmDiff * 100);
    
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                       messageAsInt:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)gettile:(CDVInvokedUrlCommand*)command {
    int x = [[command.arguments objectAtIndex:0] intValue];
    int y = [[command.arguments objectAtIndex:1] intValue];
    int z = [[command.arguments objectAtIndex:2] intValue];
    
    NSLog(@"Getting offline tile at %d/%d/%d", z, x, y);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString* tilePath = [self.offlineTileCache getTileAtX:x y:y z:z];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary* result;
            if (tilePath && tilePath.length > 0) {
                result = @{@"tile": tilePath};
            } else {
                result = @{@"error": @"error"};
            }
            
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                                           messageAsDictionary:result];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        });
    });
}

- (void)selstorage:(CDVInvokedUrlCommand*)command {
    NSString* type = [command.arguments objectAtIndex:0];
    
    // iOS implementation will use document picker
    // For now, return success - will implement document picker later
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                              messageAsString:@"Storage selection not yet implemented"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)mdnsUpdateDiscovery:(CDVInvokedUrlCommand*)command {
    NSString* mode = [command.arguments objectAtIndex:0];
    NSString* addr = [command.arguments objectAtIndex:1];
    
    [self.mdnsHandler updateDiscovery:mode address:addr];
    
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

#pragma mark - Handler callbacks

- (void)handleJsonrdzData:(NSString*)data {
    if (!self.callbackId) return;
    
    NSString* modifiedData = data;
    
    // Parse JSON to extract lat/lon and add EGM difference
    NSError* error;
    NSData* jsonData = [data dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary* json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (!error && json[@"lat"] && json[@"lon"]) {
        double lat = [json[@"lat"] doubleValue];
        double lon = [json[@"lon"] doubleValue];
        
        float egmDiff = [self.wgsToEgm wgsToEgm:lat longitude:lon];
        if (!isnan(egmDiff)) {
            NSMutableDictionary* mutableJson = [json mutableCopy];
            mutableJson[@"egmdiff"] = @(egmDiff);
            
            NSData* modifiedJsonData = [NSJSONSerialization dataWithJSONObject:mutableJson options:0 error:nil];
            if (modifiedJsonData) {
                modifiedData = [[NSString alloc] initWithData:modifiedJsonData encoding:NSUTF8StringEncoding];
            }
        }
    }
    
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                              messageAsString:modifiedData];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
}

- (void)handleTtgoStatus:(NSString*)ip {
    if (!self.callbackId) return;

    NSString* status;
    if (ip) {
        status = [NSString stringWithFormat:@"{ \"msgtype\": \"ttgostatus\", \"state\": \"online\", \"ip\": \"%@\" }", ip];
    } else {
        status = @"{ \"msgtype\": \"ttgostatus\", \"state\": \"offline\", \"ip\": \"\" }";
    }

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                              messageAsString:status];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
}

- (void)handleMdnsStatus:(NSString*)status details:(NSString*)details {
    if (!self.callbackId) return;

    NSString* msg = [NSString stringWithFormat:@"{ \"msgtype\": \"mdnsstatus\", \"status\": \"%@\", \"details\": \"%@\" }",
                     status, details ? details : @""];

    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                              messageAsString:msg];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
}

- (void)updateGps:(double)latitude longitude:(double)longitude altitude:(double)altitude bearing:(float)bearing accuracy:(float)accuracy {
    [self.jsonrdzHandler postGpsPosition:latitude longitude:longitude altitude:altitude bearing:bearing accuracy:accuracy];
    
    if (!self.callbackId) return;
    
    NSString* status = [NSString stringWithFormat:@"{ \"msgtype\": \"gps\", \"lat\": %f, \"lon\": %f, \"alt\": %f, \"dir\": %f, \"hdop\": %f }",
                       latitude, longitude, altitude, bearing, accuracy];
    
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK 
                                              messageAsString:status];
    [result setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
}

- (void)runJsonRdz:(NSString*)host port:(int)port {
    NSLog(@"Setting target host for jsonrdz handler: %@:%d", host, port);
    [self.jsonrdzHandler connectToHost:host port:port];
}

#pragma mark - Private methods

- (void)scheduleStatusUpdate {
    if (!self.running) return;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.jsonrdzHandler postAlive];
        [self scheduleStatusUpdate];
    });
}

@end