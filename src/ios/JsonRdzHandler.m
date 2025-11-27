/*
 * Copyright (C) Hansi Reiser <dl9rdz@darc.de>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#import "JsonRdzHandler.h"
#import "RdzWx.h"

@interface JsonRdzHandler () <NSStreamDelegate>

@property (nonatomic, strong) NSString *host;
@property (nonatomic, assign) int port;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic, strong) NSTimer *reconnectTimer;

@end

@implementation JsonRdzHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        self.running = NO;
        self.active = NO;
        self.buffer = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)initializeWithPlugin:(RdzWx*)plugin {
    self.plugin = plugin;
    self.active = YES;
    [self startConnectionLoop];
}

- (void)start {
    self.running = YES;
}

- (void)stop {
    self.active = NO;
    self.running = NO;
    [self closeConnection];
    [self.reconnectTimer invalidate];
    self.reconnectTimer = nil;
}

- (void)connectToHost:(NSString*)host port:(int)port {
    self.host = host;
    self.port = port;
    NSLog(@"JsonRdzHandler: Set target host %@:%d", host, port);
}

- (void)closeConnection {
    if (self.inputStream) {
        [self.inputStream close];
        [self.inputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        self.inputStream = nil;
    }

    if (self.outputStream) {
        [self.outputStream close];
        [self.outputStream removeFromRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
        self.outputStream = nil;
    }

    self.running = NO;
    [self.plugin handleTtgoStatus:nil];

    NSLog(@"JsonRdzHandler: Connection closed");
}

- (void)postGpsPosition:(double)latitude longitude:(double)longitude altitude:(double)altitude bearing:(float)bearing accuracy:(float)accuracy {
    if (!self.outputStream || self.outputStream.streamStatus != NSStreamStatusOpen) {
        return;
    }
    
    NSString *jsonString = [NSString stringWithFormat:@"{\"lat\": %f, \"lon\": %f, \"alt\": %f, \"course\": %f, \"hdop\": %f}\n",
                           latitude, longitude, altitude, bearing, accuracy];
    
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    [self.outputStream write:data.bytes maxLength:data.length];
}

- (void)postAlive {
    if (!self.outputStream || self.outputStream.streamStatus != NSStreamStatusOpen) {
        return;
    }
    
    NSString *statusString = @"{\"status\": 1}\n";
    NSData *data = [statusString dataUsingEncoding:NSUTF8StringEncoding];
    [self.outputStream write:data.bytes maxLength:data.length];
    
    NSLog(@"JsonRdzHandler: Status update sent");
}

#pragma mark - Private methods

- (void)startConnectionLoop {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self connectionLoop];
    });
}

- (void)connectionLoop {
    NSLog(@"JsonRdzHandler: Connection loop started");
    
    while (self.active) {
        if (!self.host || self.port == 0) {
            [NSThread sleepForTimeInterval:1.0];
            continue;
        }
        
        self.running = YES;
        [self attemptConnection];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.plugin handleTtgoStatus:nil];
        });
        
        self.running = NO;
        [NSThread sleepForTimeInterval:1.0];
    }
    
    NSLog(@"JsonRdzHandler: Connection loop terminated");
}

- (void)attemptConnection {
    NSLog(@"JsonRdzHandler: Attempting to connect to %@:%d", self.host, self.port);

    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;

    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.host, self.port, &readStream, &writeStream);

    if (!readStream || !writeStream) {
        NSLog(@"JsonRdzHandler: Failed to create streams");
        return;
    }

    self.inputStream = (__bridge NSInputStream *)readStream;
    self.outputStream = (__bridge NSOutputStream *)writeStream;

    [self.inputStream setDelegate:self];
    [self.outputStream setDelegate:self];

    // Schedule streams on main run loop (it's always running)
    [self.inputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];

    [self.inputStream open];
    [self.outputStream open];

    NSLog(@"JsonRdzHandler: Streams opened, waiting for connection...");

    // Set connection timeout
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.outputStream.streamStatus != NSStreamStatusOpen) {
            NSLog(@"JsonRdzHandler: Connection timeout (status: %ld)", (long)self.outputStream.streamStatus);
            [self closeConnection];
        }
    });

    // Wait for streams to connect and stay open
    while (self.running && self.active) {
        NSStreamStatus inputStatus = self.inputStream.streamStatus;
        NSStreamStatus outputStatus = self.outputStream.streamStatus;

        // Exit if either stream has error or ended
        if (inputStatus == NSStreamStatusError || inputStatus == NSStreamStatusClosed ||
            outputStatus == NSStreamStatusError || outputStatus == NSStreamStatusClosed) {
            break;
        }

        [NSThread sleepForTimeInterval:0.1];
    }

    [self closeConnection];
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventOpenCompleted:
            if (stream == self.outputStream) {
                NSLog(@"JsonRdzHandler: Connected to %@:%d", self.host, self.port);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.plugin handleTtgoStatus:self.host];
                });
            }
            break;
            
        case NSStreamEventHasBytesAvailable:
            if (stream == self.inputStream) {
                [self handleIncomingData];
            }
            break;
            
        case NSStreamEventEndEncountered:
        case NSStreamEventErrorOccurred:
            NSLog(@"JsonRdzHandler: Stream error or end encountered");
            self.running = NO;
            break;
            
        default:
            break;
    }
}

- (void)handleIncomingData {
    uint8_t buffer[1024];
    NSInteger bytesRead = [self.inputStream read:buffer maxLength:sizeof(buffer)];
    
    if (bytesRead > 0) {
        [self.buffer appendBytes:buffer length:bytesRead];
        [self processBuffer];
    }
}

- (void)processBuffer {
    NSData *data = [self.buffer copy];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSRange braceRange = [string rangeOfString:@"}"];
    while (braceRange.location != NSNotFound) {
        NSString *jsonFrame = [string substringToIndex:braceRange.location + 1];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.plugin handleJsonrdzData:jsonFrame];
        });
        
        // Remove processed frame from buffer
        NSUInteger frameLength = braceRange.location + 1;
        [self.buffer replaceBytesInRange:NSMakeRange(0, frameLength) withBytes:NULL length:0];
        
        // Update string and search for next frame
        data = [self.buffer copy];
        string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        braceRange = [string rangeOfString:@"}"];
    }
}

@end