/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "MDNSHandler.h"
#import "RdzWx.h"
#import <Network/Network.h>

@interface MDNSHandler ()

@property (nonatomic, strong) NSNetServiceBrowser *serviceBrowser;
@property (nonatomic, strong) NSMutableArray<NSNetService *> *discoveredServices;
@property (nonatomic, assign) BOOL isDiscovering;

@end

@implementation MDNSHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        self.discoveredServices = [[NSMutableArray alloc] init];
        self.isDiscovering = NO;
    }
    return self;
}

- (void)initializeWithPlugin:(RdzWx*)plugin {
    self.plugin = plugin;
}

- (void)start {
    // mDNS discovery will be started when updateDiscovery is called with "auto" mode
    NSLog(@"MDNSHandler: Initialized");
}

- (void)stop {
    [self stopDiscovery];
}

- (void)updateDiscovery:(NSString*)mode address:(NSString*)address {
    if ([mode isEqualToString:@"auto"]) {
        [self startDiscovery];
    } else {
        [self stopDiscovery];
        
        if (address && address.length > 0) {
            [self connectToManualAddress:address];
        }
    }
}

- (void)startDiscovery {
    if (self.isDiscovering) {
        return;
    }

    self.serviceBrowser = [[NSNetServiceBrowser alloc] init];
    self.serviceBrowser.delegate = self;

    [self.serviceBrowser searchForServicesOfType:@"_jsonrdz._tcp." inDomain:@"local."];
    self.isDiscovering = YES;

    [self.plugin handleMdnsStatus:@"searching" details:nil];
    NSLog(@"MDNSHandler: Started service discovery for _jsonrdz._tcp.");
}

- (void)stopDiscovery {
    if (!self.isDiscovering) {
        return;
    }

    [self.serviceBrowser stop];
    self.serviceBrowser = nil;
    [self.discoveredServices removeAllObjects];
    self.isDiscovering = NO;

    [self.plugin handleMdnsStatus:@"inactive" details:nil];
    NSLog(@"MDNSHandler: Stopped service discovery");
}

- (void)connectToManualAddress:(NSString*)address {
    NSArray *components = [address componentsSeparatedByString:@":"];
    
    NSString *host = components[0];
    int port = 14570; // Default port
    
    if (components.count > 1) {
        port = [components[1] intValue];
        if (port == 0) {
            port = 14570;
        }
    }
    
    NSLog(@"MDNSHandler: Connecting to manual address %@:%d", host, port);
    [self.plugin runJsonRdz:host port:port];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    NSLog(@"MDNSHandler: Found service: %@", service.name);

    [self.plugin handleMdnsStatus:@"found" details:service.name];
    [self.discoveredServices addObject:service];
    service.delegate = self;
    [service resolveWithTimeout:10.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    NSLog(@"MDNSHandler: Service lost: %@", service.name);
    [self.discoveredServices removeObject:service];
    [self.plugin handleMdnsStatus:@"searching" details:nil];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"MDNSHandler: Service discovery failed: %@", errorDict);
    NSString *errorMsg = [NSString stringWithFormat:@"Failed to start: %@", errorDict];
    [self.plugin handleMdnsStatus:@"error" details:errorMsg];
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser {
    NSLog(@"MDNSHandler: Service discovery stopped");
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    NSLog(@"MDNSHandler: Service resolved: %@ on port %ld", sender.hostName, (long)sender.port);
    
    if (sender.hostName && sender.port > 0) {
        [self.plugin runJsonRdz:sender.hostName port:(int)sender.port];
    }
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary<NSString *,NSNumber *> *)errorDict {
    NSLog(@"MDNSHandler: Failed to resolve service: %@, error: %@", sender.name, errorDict);
}

@end