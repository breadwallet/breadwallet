//
//  BRAppleWatchTransactionData+Factory.m
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

#import "BRAppleWatchTransactionData+Factory.h"
#import "BRTransaction+Utils.h"

@implementation BRAppleWatchTransactionData (Factory)
+ (instancetype)appleWatchTransactionDataFrom:(BRTransaction*)transaction {
    BRAppleWatchTransactionData *appleWatchTransactionData;
    if (transaction) {
        appleWatchTransactionData = [[BRAppleWatchTransactionData alloc] init];
        appleWatchTransactionData.amountText = transaction.amountText;
        appleWatchTransactionData.amountTextInLocalCurrency = transaction.localCurrencyTextForAmount;
        appleWatchTransactionData.dateText = transaction.dateText;
        switch (transaction.transactionType) {
            case BRTransactionTypeSent:
                appleWatchTransactionData.type = BRAWTransactionTypeSent;
                break;
            case BRTransactionTypeReceive:
                appleWatchTransactionData.type = BRAWTransactionTypeReceive;
                break;
            case BRTransactionTypeMove:
                appleWatchTransactionData.type = BRAWTransactionTypeMove;
                break;
            case BRTransactionTypeInvalid:
                appleWatchTransactionData.type = BRAWTransactionTypeInvalid;
                break;
        }
    }
    return appleWatchTransactionData;
}
@end
