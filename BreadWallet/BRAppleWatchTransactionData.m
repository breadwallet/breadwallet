//
//  BRAppleWatchTransactionData.m
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

#import "BRAppleWatchTransactionData.h"

#define AW_TRANSACTION_DATA_AMOUNT_KEY                      @"AW_TRANSACTION_DATA_AMOUNT_KEY"
#define AW_TRANSACTION_DATA_AMOUNT_IN_LOCAL_CURRENCY_KEY    @"AW_TRANSACTION_DATA_AMOUNT_IN_LOCAL_CURRENCY_KEY"
#define AW_TRANSACTION_DATA_DATE_KEY                        @"AW_TRANSACTION_DATA_DATE_KEY"
#define AW_TRANSACTION_DATA_TYPE_KEY                        @"AW_TRANSACTION_DATA_TYPE_KEY"

@implementation BRAppleWatchTransactionData
- (id)initWithCoder:(NSCoder *)decoder {
    if ((self = [super init])) {
        _amountText = [decoder decodeObjectForKey:AW_TRANSACTION_DATA_AMOUNT_KEY];
        _amountTextInLocalCurrency = [decoder decodeObjectForKey:AW_TRANSACTION_DATA_AMOUNT_IN_LOCAL_CURRENCY_KEY];
        _dateText = [decoder decodeObjectForKey:AW_TRANSACTION_DATA_DATE_KEY];
        _type = [[decoder decodeObjectForKey:AW_TRANSACTION_DATA_TYPE_KEY] intValue];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    if (_amountText) [encoder encodeObject:_amountText forKey:AW_TRANSACTION_DATA_AMOUNT_KEY];
    if (_amountTextInLocalCurrency) [encoder encodeObject:_amountTextInLocalCurrency
                                                   forKey:AW_TRANSACTION_DATA_AMOUNT_IN_LOCAL_CURRENCY_KEY];
    if (_dateText) [encoder encodeObject:_dateText forKey:AW_TRANSACTION_DATA_DATE_KEY];
    if (_type) [encoder encodeObject:@(_type) forKey:AW_TRANSACTION_DATA_TYPE_KEY];
}

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[self class]]) {
        BRAppleWatchTransactionData *otherTransaction = object;
        return [self.amountText isEqual:otherTransaction.amountText] &&
        [self.amountTextInLocalCurrency isEqual:otherTransaction.amountTextInLocalCurrency] &&
        [self.dateText isEqual:otherTransaction.dateText] &&
        self.type == otherTransaction.type;
    } else {
        return NO;
    }
}

@end
