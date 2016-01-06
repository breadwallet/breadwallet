//
//  BRPeer.h
//  BreadWallet
//
//  Created by Aaron Voisine on 10/9/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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


#if BITCOIN_TESTNET
#define BITCOIN_STANDARD_PORT 18333
#else
#define BITCOIN_STANDARD_PORT 8333
#endif

#define BITCOIN_TIMEOUT_CODE  1001

#define SERVICES_NODE_NETWORK 1 // services value indicating a node carries full blocks, not just headers
#define USER_AGENT            [NSString stringWithFormat:@"/breadwallet:%@/",\
                               NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]]

// explanation of message types at: https://en.bitcoin.it/wiki/Protocol_specification
#define MSG_VERSION     @"version"
#define MSG_VERACK      @"verack"
#define MSG_ADDR        @"addr"
#define MSG_INV         @"inv"
#define MSG_GETDATA     @"getdata"
#define MSG_NOTFOUND    @"notfound"
#define MSG_GETBLOCKS   @"getblocks"
#define MSG_GETHEADERS  @"getheaders"
#define MSG_TX          @"tx"
#define MSG_BLOCK       @"block"
#define MSG_HEADERS     @"headers"
#define MSG_GETADDR     @"getaddr"
#define MSG_MEMPOOL     @"mempool"
#define MSG_CHECKORDER  @"checkorder"
#define MSG_SUBMITORDER @"submitorder"
#define MSG_REPLY       @"reply"
#define MSG_PING        @"ping"
#define MSG_PONG        @"pong"
#define MSG_FILTERLOAD  @"filterload"
#define MSG_FILTERADD   @"filteradd"
#define MSG_FILTERCLEAR @"filterclear"
#define MSG_MERKLEBLOCK @"merkleblock"
#define MSG_ALERT       @"alert"
#define MSG_REJECT      @"reject" // described in BIP61: https://github.com/bitcoin/bips/blob/master/bip-0061.mediawiki

#define REJECT_INVALID     0x10 // transaction is invalid for some reason (invalid signature, output value > input, etc)
#define REJECT_SPENT       0x12 // an input is already spent
#define REJECT_NONSTANDARD 0x40 // not mined/relayed because it is "non-standard" (type or version unknown by server)
#define REJECT_DUST        0x41 // one or more output amounts are below the 'dust' threshold
#define REJECT_LOWFEE      0x42 // transaction does not have enough fee/priority to be relayed or mined

typedef union _UInt256 UInt256;
typedef union _UInt128 UInt128;

@class BRPeer, BRTransaction, BRMerkleBlock;

@protocol BRPeerDelegate<NSObject>
@required

- (void)peerConnected:(BRPeer *)peer;
- (void)peer:(BRPeer *)peer disconnectedWithError:(NSError *)error;
- (void)peer:(BRPeer *)peer relayedPeers:(NSArray *)peers;
- (void)peer:(BRPeer *)peer relayedTransaction:(BRTransaction *)transaction;
- (void)peer:(BRPeer *)peer hasTransaction:(UInt256)txHash;
- (void)peer:(BRPeer *)peer rejectedTransaction:(UInt256)txHash withCode:(uint8_t)code;

// called when the peer relays either a merkleblock or a block header, headers will have 0 totalTransactions
- (void)peer:(BRPeer *)peer relayedBlock:(BRMerkleBlock *)block;

- (void)peer:(BRPeer *)peer notfoundTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockhashes;
- (BRTransaction *)peer:(BRPeer *)peer requestedTransaction:(UInt256)txHash;

@end

typedef enum : NSInteger {
    BRPeerStatusDisconnected = 0,
    BRPeerStatusConnecting,
    BRPeerStatusConnected
} BRPeerStatus;

@interface BRPeer : NSObject<NSStreamDelegate>

@property (nonatomic, readonly) id<BRPeerDelegate> delegate;
@property (nonatomic, readonly) dispatch_queue_t delegateQueue;

// set this to the timestamp when the wallet was created to improve initial sync time (interval since refrence date)
@property (nonatomic, assign) NSTimeInterval earliestKeyTime;

@property (nonatomic, readonly) BRPeerStatus status;
@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) UInt128 address;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) uint64_t services;
@property (nonatomic, readonly) uint32_t version;
@property (nonatomic, readonly) uint64_t nonce;
@property (nonatomic, readonly) NSString *useragent;
@property (nonatomic, readonly) uint32_t lastblock;
@property (nonatomic, readonly) NSTimeInterval pingTime;
@property (nonatomic, assign) NSTimeInterval timestamp; // timestamp reported by peer (interval since refrence date)
@property (nonatomic, assign) int16_t misbehavin;

@property (nonatomic, assign) BOOL needsFilterUpdate; // set this when wallet addresses need to be added to bloom filter
@property (nonatomic, assign) uint32_t currentBlockHeight; // set this to local block height (helps detect tarpit nodes)
@property (nonatomic, assign) BOOL synced; // use this to keep track of peer state

+ (instancetype)peerWithAddress:(UInt128)address andPort:(uint16_t)port;

- (instancetype)initWithAddress:(UInt128)address andPort:(uint16_t)port;
- (instancetype)initWithAddress:(UInt128)address port:(uint16_t)port timestamp:(NSTimeInterval)timestamp
services:(uint64_t)services;
- (void)setDelegate:(id<BRPeerDelegate>)delegate queue:(dispatch_queue_t)delegateQueue;
- (void)connect;
- (void)disconnect;
- (void)sendMessage:(NSData *)message type:(NSString *)type;
- (void)sendFilterloadMessage:(NSData *)filter;
- (void)sendMempoolMessage;
- (void)sendGetheadersMessageWithLocators:(NSArray *)locators andHashStop:(UInt256)hashStop;
- (void)sendGetblocksMessageWithLocators:(NSArray *)locators andHashStop:(UInt256)hashStop;
- (void)sendInvMessageWithTxHashes:(NSArray *)txHashes;
- (void)sendGetdataMessageWithTxHashes:(NSArray *)txHashes andBlockHashes:(NSArray *)blockHashes;
- (void)sendGetaddrMessage;
- (void)sendPingMessageWithPongHandler:(void (^)(BOOL success))pongHandler;
- (void)rerequestBlocksFrom:(UInt256)blockHash; // useful to get additional transactions after a bloom filter update

@end
