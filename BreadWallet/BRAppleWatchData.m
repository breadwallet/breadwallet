//
//  BRAppleWatchData.m
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

#import "BRAppleWatchData.h"

#define AW_DATA_BALANCE_KEY                     @"AW_DATA_BALANCE_KEY"
#define AW_DATA_BALANCE_LOCAL_KEY               @"AW_DATA_BALANCE_LOCAL_KEY"
#define AW_DATA_RECEIVE_MONEY_ADDRESS           @"AW_DATA_RECEIVE_MONEY_ADDRESS"
#define AW_DATA_RECEIVE_MONEY_QR_CODE           @"AW_DATA_RECEIVE_MONEY_QR_CODE"
#define AW_DATA_TRANSACTIONS                    @"AW_DATA_TRANSACTIONS"
#define AW_DATA_LATEST_TRANSACTION              @"AW_DATA_LATEST_TRANSACTION"
#define AW_DATA_HAS_WALLET                      @"AW_DATA_HAS_WALLET"


@implementation BRAppleWatchData
- (id)initWithCoder:(NSCoder *)decoder {
    if ((self = [super init])) {
        _balance = [decoder decodeObjectForKey:AW_DATA_BALANCE_KEY];
        _balanceInLocalCurrency = [decoder decodeObjectForKey:AW_DATA_BALANCE_LOCAL_KEY];
        _receiveMoneyAddress = [decoder decodeObjectForKey:AW_DATA_RECEIVE_MONEY_ADDRESS];
        _receiveMoneyQRCodeImage = [decoder decodeObjectForKey:AW_DATA_RECEIVE_MONEY_QR_CODE];
        _lastestTransction =  [decoder decodeObjectForKey:AW_DATA_LATEST_TRANSACTION];
        _transactions = [decoder decodeObjectForKey:AW_DATA_TRANSACTIONS];
        _hasWallet = [[decoder decodeObjectForKey:AW_DATA_HAS_WALLET] boolValue];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    if (_balance) [encoder encodeObject:_balance forKey:AW_DATA_BALANCE_KEY];
    if (_balanceInLocalCurrency) [encoder encodeObject:_balanceInLocalCurrency forKey:AW_DATA_BALANCE_LOCAL_KEY];
    if (_receiveMoneyAddress) [encoder encodeObject:_receiveMoneyAddress forKey:AW_DATA_RECEIVE_MONEY_ADDRESS];
    if (_receiveMoneyQRCodeImage) [encoder encodeObject:_receiveMoneyQRCodeImage forKey:AW_DATA_RECEIVE_MONEY_QR_CODE];
    if (_lastestTransction) [encoder encodeObject:_lastestTransction forKey:AW_DATA_LATEST_TRANSACTION];
    if (_transactions) [encoder encodeObject:_transactions forKey:AW_DATA_TRANSACTIONS];
    if (_hasWallet) [encoder encodeObject:@(_hasWallet) forKey:AW_DATA_HAS_WALLET];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@,%@,%@,%@,%@,image size:%@",
            _balance, _balanceInLocalCurrency, _receiveMoneyAddress, @([_transactions count]), _lastestTransction,
            @(_receiveMoneyQRCodeImage.size.height)];
}

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[self class]]) {
        BRAppleWatchData *otherAppleWatchData = object;
        return [self.balance isEqual:otherAppleWatchData.balance] &&
        [self.balanceInLocalCurrency isEqual:otherAppleWatchData.balanceInLocalCurrency] &&
        [self.receiveMoneyAddress isEqual:otherAppleWatchData.receiveMoneyAddress] &&
        [self.lastestTransction isEqual:otherAppleWatchData.lastestTransction] &&
        [self.transactions isEqual:otherAppleWatchData.transactions] &&
        self.hasWallet == otherAppleWatchData.hasWallet;
    } else {
        return NO;
    }
}
@end
