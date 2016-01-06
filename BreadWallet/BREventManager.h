//
//  BREventManager.h
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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface BREventManager : NSObject

// typically this class is used as a singleton so this is how you should get a handle on the global event manager
+ (instancetype)sharedEventManager;

// convenience method for [[BREventManager sharedEventManager] saveEvent:(NSString*)]
+ (void)saveEvent:(NSString *)eventName;

// convenience method for
// [[BReventManager sharedEventManager] saveEvent:(NSString *) withAttributes:(NSDictionary *)attributes
+ (void)saveEvent:(NSString *)eventName withAttributes:(NSDictionary *)attributes;

// starts the event manager and begins listening to app lifecycle events if the user has both:
//   1: is in the sample group
//   2: has agreed to be in the sample group
- (void)up;

// quits the event manager, unhooking from all app lifecycle events
- (void)down;

// begins a sync of event data to the server
- (void)sync;

// persists an event to storage to later be sent to the server in a batch
- (void)saveEvent:(NSString *)eventName;

// same as saveEvent but allows you to save some arbitrary key->value data (must be string->string)
- (void)saveEvent:(NSString *)eventName withAttributes:(NSDictionary *)attributes;

// returns whether or not this instance of BREventManager has been selected to be in a sample group
- (BOOL)isInSampleGroup;

// retruns whether or not (if this instance is in the sample group) we have asked permission from the
// user of the application before
- (BOOL)hasAskedForPermission;

// returns whether or not (if this instance is in the sample group) we have acquired permission from the
// user of the application before
- (BOOL)hasAcquiredPermission;

// displays a UI in the view controller prompting the user for permission to save event data
// the value of whether or not the user agrees will be returned to the completionCallback
- (void)acquireUserPermissionInViewController:(UIViewController *)viewController
                                 withCallback:(void (^)(BOOL didGetPermission))completionCallback;


@end
