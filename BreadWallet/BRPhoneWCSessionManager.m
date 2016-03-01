//
//  BRPhoneWCSessionManager.h
//  BreadWallet
//
//  Created by Henry on 10/27/15.
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

#import "BRPhoneWCSessionManager.h"
#import <WatchConnectivity/WatchConnectivity.h>
#import "BRAppleWatchSharedConstants.h"
#import "BRWalletManager.h"
#import "BRPaymentRequest.h"
#import "UIImage+Utils.h"
#import "BRAppleWatchTransactionData+Factory.h"
#import "BRPeerManager.h"
#import "BRTransaction+Utils.h"


@interface BRPhoneWCSessionManager()<WCSessionDelegate>
@property WCSession *session;
@end


@implementation BRPhoneWCSessionManager

+ (instancetype)sharedInstance {
    static BRPhoneWCSessionManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        // prevent pre watchOS iOS access the feature
        if ([WCSession class] && [WCSession isSupported]) {
            self.session = [WCSession defaultSession];
            self.session.delegate = self;
            [self.session activateSession];
            [self sendApplicationContext];
            [[NSNotificationCenter defaultCenter]
             addObserver:self selector:@selector(sendDataUpdateNotificationToWatch)
             name:BRWalletBalanceChangedNotification object:nil];
        }
    }
    return self;
}

- (BOOL)reachable
{
    return self.session.reachable;
}

- (void)notifyTransactionString:(NSString *)notification
{
    if (self.reachable) {
        NSDictionary *msg = @{
            AW_PHONE_NOTIFICATION_KEY: notification,
            AW_PHONE_NOTIFICATION_TYPE_KEY: @(AWPhoneNotificationTypeTxReceive)
        };
    
        [self.session sendMessage:msg replyHandler:^(NSDictionary<NSString *,id> * _Nonnull replyMessage) {
            NSLog(@"received response from balance update notification to watch: %@", replyMessage);
        } errorHandler:^(NSError * _Nonnull error) {
            NSLog(@"got an error sending a balance update notification to watch");
        }];
        NSLog(@"sent a balance update notification to watch: %@", msg);
    }
}

#pragma mark - WKSession delegate
- (void)session:(WCSession *)session
didReceiveMessage:(NSDictionary<NSString *, id> *)message
   replyHandler:(void(^)(NSDictionary<NSString *, id> *replyMessage))replyHandler {
    
    NSLog(@"BRPhoneWCSessionManager didReceiveMessage %@", message);
    
    if ([message[AW_SESSION_REQUEST_TYPE] integerValue] == AWSessionRquestTypeFetchData) {
        switch ([message[AW_SESSION_REQUEST_DATA_TYPE_KEY] integerValue]) {
            case AWSessionRquestDataTypeApplicationContextData:
                [self handleApplicationContextDataRequest:message replyHandler:replyHandler];
                // sync with peer whenever there is a request coming, so we can update watch side. 
                [(id<UIApplicationDelegate>)[UIApplication sharedApplication].delegate
                    application:[UIApplication sharedApplication]
                 performFetchWithCompletionHandler:^(UIBackgroundFetchResult result) {
                     NSLog(@"watch triggered background fetch completed with result %lu", (unsigned long)result);
                }];
                break;
            case AWSessionRquestDataTypeQRCodeBits:
            {
                BRWalletManager *manager = [BRWalletManager sharedInstance];
                BRPaymentRequest *req = [BRPaymentRequest requestWithString:manager.wallet.receiveAddress];
                req.amount = [message[AW_SESSION_QR_CODE_BITS_KEY] integerValue];
                NSLog(@"watch requested a qr code amount %lld", req.amount);
                UIImage *img = [UIImage imageWithQRCodeData:req.data
                                               size:CGSizeMake(150, 150)
                                              color:[CIColor colorWithRed:0.0 green:0.0 blue:0.0]];
                NSData *dat = UIImagePNGRepresentation(img);
                replyHandler(@{AW_QR_CODE_BITS_KEY: dat});
                break;
            }
            default:
                replyHandler(@{});
        }
    } else {
        replyHandler(@{});
    }
}

#pragma mark - request handlers

- (void)handleApplicationContextDataRequest:(NSDictionary*)request
                               replyHandler:(void(^)(NSDictionary<NSString *, id> *replyMessage))replyHandler {
    NSDictionary *replay = @{AW_SESSION_RESPONSE_KEY:
                                 [NSKeyedArchiver archivedDataWithRootObject:[self applicationContextData]]};
    replyHandler(replay);
}

- (void)sendApplicationContext {
    BRAppleWatchData *appleWatchData = [self applicationContextData];
    [self.session updateApplicationContext:@{AW_APPLICATION_CONTEXT_KEY:
                                                 [NSKeyedArchiver archivedDataWithRootObject:appleWatchData]}
                                     error:nil];
}

- (void)sendDataUpdateNotificationToWatch {
    [self sendApplicationContext];
}

- (BRAppleWatchData *)applicationContextData {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSArray *transactions = manager.wallet.recentTransactions;
    UIImage *qrCodeImage = self.qrCode;
    BRAppleWatchData *appleWatchData = [[BRAppleWatchData alloc] init];
    appleWatchData.balance = [manager stringForAmount:manager.wallet.balance];
    appleWatchData.balanceInLocalCurrency = [manager localCurrencyStringForAmount:manager.wallet.balance];
    appleWatchData.receiveMoneyAddress = [BRWalletManager sharedInstance].wallet.receiveAddress;
    appleWatchData.transactions = [[self recentTransactionListFromTransactions:transactions] copy];
    appleWatchData.receiveMoneyQRCodeImage = qrCodeImage;
    appleWatchData.hasWallet = !manager.noWallet;
    if (transactions.count > 0) {
        appleWatchData.lastestTransction = [self lastTransactionStringFromTransaction:transactions[0]];
    }
    return appleWatchData;
}

- (NSString *)lastTransactionStringFromTransaction:(BRTransaction*)transaction {
    if (transaction) {
        NSString *timeDescriptionString = [self timeDescriptionStringFrom:transaction.transactionDate];
        if (timeDescriptionString == nil) {
            timeDescriptionString = transaction.dateText;
        }
        NSString *transactionTypeString;
        switch (transaction.transactionType) {
            case BRAWTransactionTypeSent:
                transactionTypeString = @"sent";
                break;
            case BRAWTransactionTypeReceive:
                transactionTypeString = @"received";
                break;
            case BRAWTransactionTypeMove:
                transactionTypeString = @"moved";
                break;
            case BRAWTransactionTypeInvalid:
                transactionTypeString = @"invalid transaction";
                break;
        }
        
        return [NSString stringWithFormat:@"%@ %@ %@ , %@",
                transactionTypeString,
                [transaction.amountText stringByReplacingOccurrencesOfString:@"-" withString:@""],
                (transaction.localCurrencyTextForAmount.length > 2) ? transaction.localCurrencyTextForAmount: @"",
                timeDescriptionString];
    }
    return @"no transaction";
}

- (NSString *)timeDescriptionStringFrom:(NSDate*) date{
    if (date) {
        NSDate *now = [NSDate date];
        NSTimeInterval secondsSinceTransaction = [now timeIntervalSinceDate:date];
        if (secondsSinceTransaction < 60) {
            return @"just now";
        } else if ( secondsSinceTransaction / 60 < 60) {
            return [NSString stringWithFormat:@"%@ minutes agao", @((NSInteger) (secondsSinceTransaction / 60))];
        } else if ( secondsSinceTransaction / 60 / 60 < 24 ) {
            return [NSString stringWithFormat:@"%@ hours agao", @((NSInteger) (secondsSinceTransaction / 60 / 60))];
        }
    }
    return nil;
}

- (UIImage *)qrCode {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSData *req = [BRPaymentRequest requestWithString:manager.wallet.receiveAddress].data;
    return [UIImage imageWithQRCodeData:req
                                   size:CGSizeMake(150, 150)
                                  color:[CIColor colorWithRed:0.0 green:0.0 blue:0.0]];
}

#pragma mark - data helper methods

- (NSArray *)recentTransactionListFromTransactions:(NSArray*)transactions {
    NSMutableArray *transactionListData = [[NSMutableArray alloc] init];
    for ( BRTransaction *transaction in transactions) {
        [transactionListData addObject:[BRAppleWatchTransactionData appleWatchTransactionDataFrom:transaction]];
    }
    return transactionListData;
}

@end
