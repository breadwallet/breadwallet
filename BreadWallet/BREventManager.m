//
//  BREventManager.m
//  BreadWallet
//
//  Created by Samuel Sutch on 9/8/15.
//  Copyright (c) 2015 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BREventManager.h"
#import "BRPeerManager.h"
#import "BREventConfirmView.h"
#import "UIImage+Utils.h"

#define HAS_DETERMINED_SAMPLE_GROUP     @"has_determined_sample_group"
#define IS_IN_SAMPLE_GROUP              @"is_in_sample_group"
#define HAS_PROMPTED_FOR_PERMISSION     @"has_prompted_for_permission"
#define HAS_ACQUIRED_PERMISSION         @"has_acquired_permission"
#define EVENT_SERVER_URL                [NSURL URLWithString:@"https://api.breadwallet.com/events"]
#define SAMPLE_CHANCE                   10

#if ! EVENT_LOGGING
#define NSLog(...)
#endif


@interface BREventManager ()

@property NSString *sessionId;
@property NSOperationQueue *myQueue;
@property NSDictionary *eventToNotifications;
@property BOOL isConnected;

@property NSMutableArray *_buffer;

- (BOOL)shouldAskForPermission;
- (BOOL)hasAskedForPermission;
- (BOOL)shouldRecordData;

- (void)_pushEventNamed:(NSString *)evtName withAttributes:(NSDictionary *)attrs;
- (NSDictionary *)_eventTupleArrayToDictionary:(NSArray *)eventTuples;
- (NSString *)_unsentDataDirectory;
- (void)_persistToDisk;
- (void)_sendToServer;
- (void)_removeData;

@end

@implementation BREventManager

- (instancetype)init
{
    if (self = [super init]) {
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        self.sessionId = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
        CFRelease(uuid);
        self.myQueue = [[NSOperationQueue alloc] init];
        self.myQueue.maxConcurrentOperationCount = 1;
        self.eventToNotifications = @{@"foreground": UIApplicationDidBecomeActiveNotification,
                                      @"background": UIApplicationDidEnterBackgroundNotification,
                                      @"sync_started": BRPeerManagerSyncStartedNotification,
                                      @"sync_finished": BRPeerManagerSyncFinishedNotification,
                                      @"sync_failed": BRPeerManagerSyncFailedNotification};
        self.isConnected = NO;
        self._buffer = [NSMutableArray array];
    }
    return self;
}

+ (instancetype)sharedEventManager
{
    static id _sharedEventMgr;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // determine if user is in sample group. it's inside the dispatch_once so it happens
        // exactly once per startup
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        if (![defs boolForKey:HAS_DETERMINED_SAMPLE_GROUP]) {
            u_int32_t chosenNumber = arc4random_uniform(100);
            NSLog(@"BREventManager chosen number %d < %d", chosenNumber, SAMPLE_CHANCE);
            bool isInSample = chosenNumber < SAMPLE_CHANCE;
            [defs setBool:isInSample forKey:IS_IN_SAMPLE_GROUP];
            [defs setBool:YES forKey:HAS_DETERMINED_SAMPLE_GROUP];
        }
        
        // allocate the singleton
        _sharedEventMgr = [[self alloc] init];
    });
    
    return _sharedEventMgr;
}

+ (void)saveEvent:(NSString *)eventName
{
    [[self sharedEventManager] saveEvent:eventName];
}

+ (void)saveEvent:(NSString *)eventName withAttributes:(NSDictionary *)attributes
{
    [[self sharedEventManager] saveEvent:eventName withAttributes:attributes];
}

- (void)up
{
    if (self.isConnected) {
        return;
    }
    // map NSNotifications to events
    [self.eventToNotifications enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [[NSNotificationCenter defaultCenter]
         addObserverForName:obj object:nil queue:self.myQueue
         usingBlock:^(NSNotification *note) {
             [self saveEvent:key];
             NSLog(@"BREventManager received notification %@", note.name);
             if ([note.name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
                 [self _persistToDisk];
                 [self _sendToServer];
             }
         }];
    }];
    self.isConnected = YES;
}

- (void)down
{
    if (!self.isConnected) {
        return;
    }
    // remove listeners for NSNotifications
    [self.eventToNotifications.allValues enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:obj object:nil];
    }];
}

- (void)saveEvent:(NSString *)eventName
{
    [self _pushEventNamed:eventName withAttributes:@{}];
}

- (void)saveEvent:(NSString *)eventName withAttributes:(NSDictionary *)attributes
{
    [self _pushEventNamed:eventName withAttributes:attributes];
}

- (BOOL)isInSampleGroup
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:IS_IN_SAMPLE_GROUP];
}

- (BOOL)hasAcquiredPermission
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:HAS_ACQUIRED_PERMISSION];
}

- (BOOL)hasAskedForPermission
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:HAS_PROMPTED_FOR_PERMISSION];
}

- (BOOL)shouldAskForPermission
{
    NSLog(@"---Sampling Metadata---");
    NSLog(@"User is in sample group: %d", [self isInSampleGroup]);
    NSLog(@"User is been asked for permission: %d", [self hasAskedForPermission]);
    NSLog(@"User has approved event collection: %d", [self hasAcquiredPermission]);
    return [self isInSampleGroup] && ![self hasAskedForPermission];
}

- (BOOL)shouldRecordData
{
    return [self isInSampleGroup] && [self hasAcquiredPermission];
}

- (void)acquireUserPermissionInViewController:(UIViewController *)viewController
                                 withCallback:(void (^)(BOOL))completionCallback
{
    if (![self shouldAskForPermission]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0),
                       dispatch_get_main_queue(), ^{
                           if (completionCallback) completionCallback([self shouldRecordData]);
                       });
        return; // no need to run if the user isn't in sample group or has already been asked for permission
    }
    
    // grab a blurred image for the background
    UIGraphicsBeginImageContext(viewController.view.bounds.size);
    [viewController.view drawViewHierarchyInRect:viewController.view.bounds afterScreenUpdates:NO];
    UIImage *bgImg = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIImage *blurredBgImg = [bgImg blurWithRadius:3];
    
    // display the popup
    __weak BREventConfirmView *eventConfirmView =
        [[[NSBundle mainBundle] loadNibNamed:@"BREventConfirmView" owner:nil options:nil] objectAtIndex:0];
    eventConfirmView.image = blurredBgImg;
    eventConfirmView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    eventConfirmView.frame = viewController.view.bounds;
    eventConfirmView.alpha = 0;
    [viewController.view addSubview:eventConfirmView];
    
    [UIView animateWithDuration:.5 animations:^{
        eventConfirmView.alpha = 1;
    }];
    [self saveEvent:@"ask_for_data_collection"];
    
    eventConfirmView.completionHandler = ^(BOOL didApprove) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:HAS_PROMPTED_FOR_PERMISSION];
        [[NSUserDefaults standardUserDefaults] setBool:didApprove forKey:HAS_ACQUIRED_PERMISSION];
        
        if (didApprove) {
            [self saveEvent:@"approve_data_collection"];
        }
        
        [UIView animateWithDuration:.5 animations:^{
            eventConfirmView.alpha = 0;
        } completion:^(BOOL finished) {
            if (completionCallback) completionCallback(didApprove);
            [eventConfirmView removeFromSuperview];
        }];
    };
}

- (void)sync
{
    if ([self shouldRecordData]) {
        [self _sendToServer];
    } else {
        [self _removeData]; // if we aren't syncing data with the server just remove all files
    }
}

# pragma mark -

- (void)_pushEventNamed:(NSString *)evtName withAttributes:(NSDictionary *)attrs
{
    [self.myQueue addOperationWithBlock:^{
#if DEBUG // notify when in debug mode
        [attrs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if (![key isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSString class]]) {
                NSLog(@"warning: key or value in attributes dictionary is not of type string, "
                      @"will be implicitly converted");
            }
        }];
#endif
        NSMutableDictionary *safeDict = [NSMutableDictionary dictionary];
        [attrs enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            [safeDict setObject:[obj description] forKey:[key description]];
        }];
        
        // we push a 4-tuple into the buffer consisting of (current_time, event_name, event_attributes)
        long long currentTimeMillis = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        NSArray *tuple = @[self.sessionId, [NSNumber numberWithLongLong:currentTimeMillis], evtName, attrs];
        [self._buffer addObject:tuple];
        NSLog(@"BREventManager Saved event %@ with attributes %@", evtName, attrs);
    }];
}

- (NSString *)_unsentDataDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return [documentsDirectory stringByAppendingPathComponent:@"/event-data"];
}

- (NSDictionary *)_eventTupleArrayToDictionary:(NSArray *)eventTuples
{
    NSString *ver = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSMutableArray *evts = [NSMutableArray array];
    NSDictionary *retDict = @{@"deviceType": @(0),
                              @"appVersion": ver,
                              @"events": evts};
    [eventTuples enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[NSArray class]] && [obj count] >= 4) {
            [evts addObject:@{@"sessionId": obj[0],
                              @"time": obj[1],
                              @"eventName": obj[2],
                              @"metadata": obj[3]}];
        }
    }];
    return retDict;
}

- (void)_persistToDisk
{
    [self.myQueue addOperationWithBlock:^{
        // create the event-data directory if it does not exist
        NSError *error;
        NSString *dataDir = [self _unsentDataDirectory];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:dataDir]) {
            if (![[NSFileManager defaultManager] createDirectoryAtPath:dataDir withIntermediateDirectories:NO
                                                            attributes:nil error:&error]) {
                NSLog(@"Unable to create directory for storing event data: %@", error);
                return;
            }
        }
        // create a uuid for the file name. it doesnt matter what the file is named. we will erase the file
        // every time we sync data to the server. the file could also contain multiple sessionIds so we don't
        // want to name it after the sessionId
        CFUUIDRef uuid = CFUUIDCreate(NULL);
        NSString *baseName = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
        CFRelease(uuid);
        NSString *fullPath = [dataDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@.json", baseName]];
        
        // now write to disk
        NSOutputStream *os = [[NSOutputStream alloc] initToFileAtPath:fullPath append:NO];
        [os open];
        if (![NSJSONSerialization writeJSONObject:self._buffer toStream:os options:0 error:&error]) {
            NSLog(@"Unable to write JSON for events file: %@", error);
        }
        [os close];
        
        // empty the buffer if we can't write JSON data, it's likely an unrecoverable error anyway
        [self._buffer removeAllObjects];
    }];
}

- (void)_sendToServer
{
    [self.myQueue addOperationWithBlock:^{
        // send any persisted data to the server
        NSError *error = nil;
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self _unsentDataDirectory]
                                                                             error:&error];
        if (error != nil) {
            NSLog(@"Unable to read contents of event data directory: %@", error);
            return; // bail here as this is likely unrecoverable
        }
        
        [files enumerateObjectsUsingBlock:^(id baseName, NSUInteger idx, BOOL *stop) {
            // perform upload
            [self.myQueue addOperationWithBlock:^{
                // 1: read the json in
                NSError *readError = nil;
                NSString *fileName = [[self _unsentDataDirectory] stringByAppendingPathComponent:
                                      [NSString stringWithFormat:@"/%@", baseName]];
                NSInputStream *ins = [[NSInputStream alloc] initWithFileAtPath:fileName];
                [ins open];
                NSArray *inArray = [NSJSONSerialization JSONObjectWithStream:ins options:0 error:&readError];
                if (readError != nil) {
                    NSLog(@"Unable to read json event file %@: %@", fileName, readError);
                    return; // bail out here as we likely cant recover from this error
                }
                
                // 2: transform it into the json data the server expects
                NSDictionary *eventDump = [self _eventTupleArrayToDictionary:inArray];
                NSError *serializeErr = nil;
                NSData *body = [NSJSONSerialization dataWithJSONObject:eventDump options:0 error:&serializeErr];
                if (serializeErr != nil) {
                    NSLog(@"Unable to jsonify event dump %@", serializeErr);
                    return; // bail out as who knows why this will fail
                }
                
                // 3. send off the request and await response
                NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:EVENT_SERVER_URL];
                req.HTTPMethod = @"POST";
                [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
                
                NSURLSessionConfiguration *seshConf = [NSURLSessionConfiguration defaultSessionConfiguration];
                NSURLSession *urlSesh = [NSURLSession sessionWithConfiguration:seshConf];
                NSURLSessionUploadTask *uploadTask =
                    [urlSesh uploadTaskWithRequest:req fromData:body completionHandler:
                     ^(NSData *data, NSURLResponse *response, NSError *connectionError) {
                         NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                         if (httpResponse.statusCode != 201) { // we should expect to receive a 201
                             NSLog(@"Error uploading event data to server: STATUS=%ld, connErr=%@ data=%@",
                                   (long)httpResponse.statusCode, connectionError,
                                   [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                         } else {
                             NSLog(@"Successfully sent event data to server %@ => %ld data=%@",
                                   fileName, (long)httpResponse.statusCode,
                                   [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                         }
                         
                         // 4. remove the file from disk since we no longer need it
                         [self.myQueue addOperationWithBlock:^{
                             NSError *removeErr = nil;
                             if (![[NSFileManager defaultManager] removeItemAtPath:fileName error:&removeErr]) {
                                 NSLog(@"Unable to remove events file at path %@: %@", fileName, removeErr);
                             }
                         }];
                     }];
                [uploadTask resume];
            }];
        }];
    }];
}

- (void)_removeData
{
    [self.myQueue addOperationWithBlock:^{
        // send any persisted data to the server
        NSError *error = nil;
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self _unsentDataDirectory]
                                                                             error:&error];
        if (error != nil) {
            NSLog(@"Unable to read contents of event data directory: %@", error);
            return; // bail here as this is likely unrecoverable
        }
        
        [files enumerateObjectsUsingBlock:^(id baseName, NSUInteger idx, BOOL *stop) {
            NSString *fileName = [[self _unsentDataDirectory] stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"/%@", baseName]];
            NSError *removeErr = nil;
            if (![[NSFileManager defaultManager] removeItemAtPath:fileName error:&removeErr]) {
                NSLog(@"Unable to remove events file at path %@: %@", fileName, removeErr);
            }
        }];
    }];
}

@end
