//
//  BRTxHistoryViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 6/11/13.
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

#import "BRTxHistoryViewController.h"
#import "BRRootViewController.h"
#import "BRSettingsViewController.h"
#import "BRTxDetailViewController.h"
#import "BRSeedViewController.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "BRTransaction.h"
#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "BREventManager.h"
#import "breadwallet-Swift.h"

#define TRANSACTION_CELL_HEIGHT 75

static NSString *dateFormat(NSString *template)
{
    NSString *format = [NSDateFormatter dateFormatFromTemplate:template options:0 locale:[NSLocale currentLocale]];
    
    format = [format stringByReplacingOccurrencesOfString:@", " withString:@" "];
    format = [format stringByReplacingOccurrencesOfString:@" a" withString:@"a"];
    format = [format stringByReplacingOccurrencesOfString:@"hh" withString:@"h"];
    format = [format stringByReplacingOccurrencesOfString:@" ha" withString:@"@ha"];
    format = [format stringByReplacingOccurrencesOfString:@"HH" withString:@"H"];
    format = [format stringByReplacingOccurrencesOfString:@"H '" withString:@"H'"];
    format = [format stringByReplacingOccurrencesOfString:@"H " withString:@"H'h' "];
    format = [format stringByReplacingOccurrencesOfString:@"H" withString:@"H'h'"
              options:NSBackwardsSearch|NSAnchoredSearch range:NSMakeRange(0, format.length)];
    return format;
}

@interface BRTxHistoryViewController ()

@property (nonatomic, strong) IBOutlet UIView *logo;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *lock;

@property (nonatomic, strong) NSArray *transactions;
@property (nonatomic, assign) BOOL moreTx;
@property (nonatomic, strong) NSMutableDictionary *txDates;
@property (nonatomic, strong) id backgroundObserver, balanceObserver, txStatusObserver;
@property (nonatomic, strong) id syncStartedObserver, syncFinishedObserver, syncFailedObserver;
@property (nonatomic, strong) UIImageView *wallpaper;
@property (nonatomic, strong) BRWebViewController *buyController;

@end

@implementation BRTxHistoryViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.txDates = [NSMutableDictionary dictionary];
    self.wallpaper = [[UIImageView alloc] initWithFrame:self.navigationController.view.bounds];
    self.wallpaper.image = [UIImage imageNamed:@"wallpaper-default"];
    self.wallpaper.contentMode = UIViewContentModeBottomLeft;
    self.wallpaper.clipsToBounds = YES;
    self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2,
                                        self.navigationController.view.frame.size.height -
                                        self.wallpaper.frame.size.height/2);
    [self.navigationController.view insertSubview:self.wallpaper atIndex:0];
    self.navigationController.delegate = self;
    self.moreTx = YES;
    
    self.buyController = [[BRWebViewController alloc] initWithBundleName:@"bread-buy"];
    [self.buyController preload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
#if SNAPSHOT
    BRTransaction *tx = [[BRTransaction alloc] initWithInputHashes:@[uint256_obj(UINT256_ZERO)] inputIndexes:@[@(0)]
                         inputScripts:@[[NSData data]] outputAddresses:@[@""] outputAmounts:@[@(0)]];
    
    manager.localCurrencyCode = [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode];
    self.tableView.showsVerticalScrollIndicator = NO;
    self.moreTx = YES;
    manager.didAuthenticate = YES;
    [self unlock:nil];
    tx.txHash = UINT256_ZERO;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.transactions = @[tx, tx, tx, tx, tx, tx];
        [self.tableView reloadData];
        self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [manager stringForAmount:42980000],
                                     [manager localCurrencyStringForAmount:42980000]];
    });

    return;
#endif

    if (! manager.didAuthenticate) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.transactions = manager.wallet.recentTransactions;
           
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        });
    }
    else [self unlock:nil];

    if (! self.backgroundObserver) {
        self.backgroundObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                self.moreTx = YES;
                self.transactions = manager.wallet.recentTransactions;
                [self.tableView reloadData];
                self.navigationItem.titleView = self.logo;
                self.navigationItem.rightBarButtonItem = self.lock;
            }];
    }

    if (! self.balanceObserver) {
        self.balanceObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                BRTransaction *tx = self.transactions.firstObject;

                self.transactions = manager.wallet.recentTransactions;

                if (! [self.navigationItem.title isEqual:NSLocalizedString(@"syncing...", nil)]) {
                    if (! manager.didAuthenticate) self.navigationItem.titleView = self.logo;
                    self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)",
                                                 [manager stringForAmount:manager.wallet.balance],
                                                 [manager localCurrencyStringForAmount:manager.wallet.balance]];
                }

                if (self.transactions.firstObject != tx) {
                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
                }
                else [self.tableView reloadData];
            }];
    }

    if (! self.txStatusObserver) {
        self.txStatusObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                self.transactions = manager.wallet.recentTransactions;
                [self.tableView reloadData];
            }];
    }
    
    if (! self.syncStartedObserver) {
        self.syncStartedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncStartedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if ([[BRPeerManager sharedInstance]
                     timestampForBlockHeight:[BRPeerManager sharedInstance].lastBlockHeight] + 60*60*24*7 <
                    [NSDate timeIntervalSinceReferenceDate] &&
                    manager.seedCreationTime + 60*60*24 < [NSDate timeIntervalSinceReferenceDate]) {
                    self.navigationItem.titleView = nil;
                    self.navigationItem.title = NSLocalizedString(@"syncing...", nil);
                }
            }];
    }
    
    if (! self.syncFinishedObserver) {
        self.syncFinishedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFinishedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if (! manager.didAuthenticate) self.navigationItem.titleView = self.logo;
                self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)",
                                             [manager stringForAmount:manager.wallet.balance],
                                             [manager localCurrencyStringForAmount:manager.wallet.balance]];
            }];
    }
    
    if (! self.syncFailedObserver) {
        self.syncFailedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFailedNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                if (! manager.didAuthenticate) self.navigationItem.titleView = self.logo;
                self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)",
                                             [manager stringForAmount:manager.wallet.balance],
                                             [manager localCurrencyStringForAmount:manager.wallet.balance]];
            }];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) {
        //BUG: XXX this isn't triggered from start/recover new wallet
        if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
        self.backgroundObserver = nil;
        if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
        self.balanceObserver = nil;
        if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
        self.txStatusObserver = nil;
        if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
        self.syncStartedObserver = nil;
        if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
        self.syncFinishedObserver = nil;
        if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
        self.syncFailedObserver = nil;
        self.wallpaper.clipsToBounds = YES;
    }

    [super viewWillDisappear:animated];
}

//- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
//{
//    [super prepareForSegue:segue sender:sender];
//
//    [segue.destinationViewController setTransitioningDelegate:self];
//    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
//}

- (void)dealloc
{
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
    if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
}

- (uint32_t)blockHeight
{
    static uint32_t height = 0;
    uint32_t h = [BRPeerManager sharedInstance].lastBlockHeight;
    
    if (h > height) height = h;
    return height;
}

- (void)setTransactions:(NSArray *)transactions
{
    uint32_t height = self.blockHeight;

    if (transactions.count <= 5) self.moreTx = NO;
    _transactions = [transactions subarrayWithRange:NSMakeRange(0, (self.moreTx) ? 5 : transactions.count)];
    if ([BRWalletManager sharedInstance].didAuthenticate) return;

    if ([self.navigationItem.title isEqual:NSLocalizedString(@"syncing...", nil)]) {
        _transactions = @[];
        if (transactions.count > 0) self.moreTx = YES;
    }
    else {
        for (BRTransaction *tx in _transactions) {
            if (tx.blockHeight == TX_UNCONFIRMED || (tx.blockHeight > height - 5 && tx.blockHeight <= height)) continue;
            _transactions = [transactions subarrayWithRange:NSMakeRange(0, [transactions indexOfObject:tx])];
            self.moreTx = YES;
            break;
        }
    }
}

- (void)setBackgroundForCell:(UITableViewCell *)cell tableView:(UITableView *)tableView indexPath:(NSIndexPath *)path
{    
    [cell viewWithTag:100].hidden = (path.row > 0);
    [cell viewWithTag:101].hidden = (path.row + 1 < [self tableView:tableView numberOfRowsInSection:path.section]);
}

- (NSString *)dateForTx:(BRTransaction *)tx
{
    static NSDateFormatter *monthDayHourFormatter = nil;
    static NSDateFormatter *yearMonthDayHourFormatter = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{ // BUG: need to watch for NSCurrentLocaleDidChangeNotification
        monthDayHourFormatter = [NSDateFormatter new];
        monthDayHourFormatter.dateFormat = dateFormat(@"Mdja");
        yearMonthDayHourFormatter = [NSDateFormatter new];
        yearMonthDayHourFormatter.dateFormat = dateFormat(@"yyMdja");
    });
    
    NSString *date = self.txDates[uint256_obj(tx.txHash)];
    NSTimeInterval now = [[BRPeerManager sharedInstance] timestampForBlockHeight:TX_UNCONFIRMED];
    NSTimeInterval year = now - 364*24*60*60;

    if (date) return date;

    NSTimeInterval txTime = (tx.timestamp > 1) ? tx.timestamp : now;
    NSDateFormatter *desiredFormatter = (txTime > year) ? monthDayHourFormatter : yearMonthDayHourFormatter;
    
    date = [desiredFormatter stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:txTime]];
    date = [date stringByReplacingOccurrencesOfString:@"am" withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"pm" withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"AM" withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"PM" withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"a.m." withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"p.m." withString:@"p"];
    date = [date stringByReplacingOccurrencesOfString:@"A.M." withString:@"a"];
    date = [date stringByReplacingOccurrencesOfString:@"P.M." withString:@"p"];
    if (tx.blockHeight != TX_UNCONFIRMED) self.txDates[uint256_obj(tx.txHash)] = date;
    return date;
}

#pragma mark - IBAction

- (IBAction)done:(id)sender
{
    [BREventManager saveEvent:@"tx_history:dismiss"];
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)unlock:(id)sender
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];

    if (sender) [BREventManager saveEvent:@"tx_history:unlock"];
    if (! manager.didAuthenticate && ! [manager authenticateWithPrompt:nil andTouchId:YES]) return;
    if (sender) [BREventManager saveEvent:@"tx_history:unlock_success"];
    
    self.navigationItem.titleView = nil;
    [self.navigationItem setRightBarButtonItem:nil animated:(sender) ? YES : NO];
    if (! sender && self.transactions.count > 0) [self.tableView reloadData];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.transactions = manager.wallet.recentTransactions;
        
        dispatch_async(dispatch_get_main_queue(), ^{ // BUG: XXXX row animation is broken
            if (sender && self.transactions.count > 0) {
                [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                 withRowAnimation:UITableViewRowAnimationAutomatic];
            }
            else [self.tableView reloadData];
        });
    });
}

- (IBAction)scanQR:(id)sender
{
    //TODO: show scanner in settings rather than dismissing
    [BREventManager saveEvent:@"tx_history:scan_qr"];
    UINavigationController *nav = (id)self.navigationController.presentingViewController;

    nav.view.alpha = 0.0;

    [nav dismissViewControllerAnimated:NO completion:^{
        [(id)((BRRootViewController *)nav.viewControllers.firstObject).sendViewController scanQR:nil];
        [UIView animateWithDuration:0.1 delay:1.5 options:0 animations:^{ nav.view.alpha = 1.0; } completion:nil];
    }];
}

- (IBAction)showTx:(id)sender
{
    [BREventManager saveEvent:@"tx_history:show_tx"];
    BRTxDetailViewController *detailController
        = [self.storyboard instantiateViewControllerWithIdentifier:@"TxDetailViewController"];
    detailController.transaction = sender;
    detailController.txDateString = [self dateForTx:sender];
    [self.navigationController pushViewController:detailController animated:YES];
}

- (IBAction)more:(id)sender
{
    [BREventManager saveEvent:@"tx_history:more"];
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSUInteger txCount = self.transactions.count;
    
    [self unlock:sender];
    if (! manager.didAuthenticate) return;
    
    [self.tableView beginUpdates];
    [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:txCount inSection:0]]
     withRowAnimation:UITableViewRowAnimationFade];
    self.moreTx = NO;
    self.transactions = manager.wallet.recentTransactions;
    
    NSMutableArray *transactions = [NSMutableArray arrayWithCapacity:self.transactions.count];
    
    while (txCount < self.transactions.count) {
        [transactions addObject:[NSIndexPath indexPathForRow:txCount++ inSection:0]];
    }
    
    [self.tableView insertRowsAtIndexPaths:transactions withRowAnimation:UITableViewRowAnimationTop];
    [self.tableView endUpdates];
}

- (void)showBuy
{
    [self presentViewController:self.buyController animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
            if (self.transactions.count == 0) return 1;
            return (self.moreTx) ? self.transactions.count + 1 : self.transactions.count;

        case 1:
            return 3;

        case 2:
            return 1;
    }

    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *noTxIdent = @"NoTxCell", *transactionIdent = @"TransactionCell", *actionIdent = @"ActionCell",
                    *disclosureIdent = @"DisclosureCell";
    UITableViewCell *cell = nil;
    UILabel *textLabel, *unconfirmedLabel, *sentLabel, *localCurrencyLabel, *balanceLabel, *localBalanceLabel,
            *detailTextLabel;
    BRWalletManager *manager = [BRWalletManager sharedInstance];

    switch (indexPath.section) {
        case 0:
            if (self.moreTx && indexPath.row >= self.transactions.count) {
                cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];
                cell.textLabel.text = (indexPath.row > 0) ? NSLocalizedString(@"more...", nil) :
                                      NSLocalizedString(@"transaction history", nil);
                cell.imageView.image = nil;
            }
            else if (self.transactions.count > 0) {
                cell = [tableView dequeueReusableCellWithIdentifier:transactionIdent];
                textLabel = (id)[cell viewWithTag:1];
                detailTextLabel = (id)[cell viewWithTag:2];
                unconfirmedLabel = (id)[cell viewWithTag:3];
                localCurrencyLabel = (id)[cell viewWithTag:5];
                sentLabel = (id)[cell viewWithTag:6];
                balanceLabel = (id)[cell viewWithTag:7];
                localBalanceLabel = (id)[cell viewWithTag:8];

                BRTransaction *tx = self.transactions[indexPath.row];
                uint64_t received = [manager.wallet amountReceivedFromTransaction:tx],
                         sent = [manager.wallet amountSentByTransaction:tx],
                         balance = [manager.wallet balanceAfterTransaction:tx];
                uint32_t blockHeight = self.blockHeight;
                uint32_t confirms = (tx.blockHeight > blockHeight) ? 0 : (blockHeight - tx.blockHeight) + 1;

#if SNAPSHOT
                received = [@[@(0), @(0), @(54000000), @(0), @(0), @(93000000)][indexPath.row] longLongValue];
                sent = [@[@(1010000), @(10010000), @(0), @(82990000), @(10010000), @(0)][indexPath.row] longLongValue];
                balance = [@[@(42980000), @(43990000), @(54000000), @(0), @(82990000), @(93000000)][indexPath.row]
                           longLongValue];
                [self.txDates removeAllObjects];
                tx.timestamp = [NSDate timeIntervalSinceReferenceDate] - indexPath.row*100000;
                confirms = 6;
#endif

                sentLabel.hidden = YES;
                unconfirmedLabel.hidden = NO;
                detailTextLabel.text = [self dateForTx:tx];
                balanceLabel.text = (manager.didAuthenticate) ? [manager stringForAmount:balance] : nil;
                localBalanceLabel.text = (manager.didAuthenticate) ?
                    [NSString stringWithFormat:@"(%@)", [manager localCurrencyStringForAmount:balance]] : nil;

                if (confirms == 0 && ! [manager.wallet transactionIsValid:tx]) {
                    unconfirmedLabel.text = NSLocalizedString(@"INVALID", nil);
                    unconfirmedLabel.backgroundColor = [UIColor redColor];
                }
                else if (confirms == 0 && [manager.wallet transactionIsPostdated:tx atBlockHeight:blockHeight]) {
                    unconfirmedLabel.text = NSLocalizedString(@"post-dated", nil);
                    unconfirmedLabel.backgroundColor = [UIColor redColor];
                }
                else if (confirms == 0 && ! [manager.wallet transactionIsVerified:tx]) {
                    unconfirmedLabel.text = NSLocalizedString(@"unverified", nil);
                }
                else if (confirms < 6) {
                    if (confirms == 0) unconfirmedLabel.text = NSLocalizedString(@"0 confirmations", nil);
                    else if (confirms == 1) unconfirmedLabel.text = NSLocalizedString(@"1 confirmation", nil);
                    else unconfirmedLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%d confirmations", nil),
                                                  (int)confirms];
                }
                else {
                    unconfirmedLabel.text = nil;
                    unconfirmedLabel.hidden = YES;
                    sentLabel.hidden = NO;
                }
                
                if (sent > 0 && received == sent) {
                    textLabel.text = [manager stringForAmount:sent];
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [manager localCurrencyStringForAmount:sent]];
                    sentLabel.text = NSLocalizedString(@"moved", nil);
                    sentLabel.textColor = [UIColor blackColor];
                }
                else if (sent > 0) {
                    textLabel.text = [manager stringForAmount:received - sent];
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [manager localCurrencyStringForAmount:received - sent]];
                    sentLabel.text = NSLocalizedString(@"sent", nil);
                    sentLabel.textColor = [UIColor colorWithRed:1.0 green:0.33 blue:0.33 alpha:1.0];
                }
                else {
                    textLabel.text = [manager stringForAmount:received];
                    localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                               [manager localCurrencyStringForAmount:received]];
                    sentLabel.text = NSLocalizedString(@"received", nil);
                    sentLabel.textColor = [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                }

                if (! unconfirmedLabel.hidden) {
                    unconfirmedLabel.layer.cornerRadius = 3.0;
                    unconfirmedLabel.backgroundColor = [UIColor lightGrayColor];
                    unconfirmedLabel.text = [unconfirmedLabel.text stringByAppendingString:@"  "];
                }
                else {
                    sentLabel.layer.cornerRadius = 3.0;
                    sentLabel.layer.borderWidth = 0.5;
                    sentLabel.text = [sentLabel.text stringByAppendingString:@"  "];
                    sentLabel.layer.borderColor = sentLabel.textColor.CGColor;
                    sentLabel.highlightedTextColor = sentLabel.textColor;
                }
            }
            else cell = [tableView dequeueReusableCellWithIdentifier:noTxIdent];
            
            break;

        case 1:
            cell = [tableView dequeueReusableCellWithIdentifier:actionIdent];

            switch (indexPath.row) {
                case 0:
                    cell.textLabel.text = NSLocalizedString(@"Buy Bitcoin", nil);
                    cell.imageView.image = [UIImage imageNamed:@"bitcoin-buy-blue-small"];
                    cell.imageView.alpha = 1.0;
                    break;
                    
                case 1:
                    cell.textLabel.text = NSLocalizedString(@"Import Private Key", nil);
                    cell.imageView.image = [UIImage imageNamed:@"cameraguide-blue-small"];
                    cell.imageView.alpha = 1.0;
                    break;

                case 2:
                    cell.textLabel.text = NSLocalizedString(@"Rescan Blockchain", nil);
                    cell.imageView.image = [UIImage imageNamed:@"rescan"];
                    cell.imageView.alpha = 0.75;
                    break;
            }
            
            break;

        case 2:
            cell = [tableView dequeueReusableCellWithIdentifier:disclosureIdent];
            cell.textLabel.text = NSLocalizedString(@"Settings", nil);
            break;
    }
    
    [self setBackgroundForCell:cell tableView:tableView indexPath:indexPath];
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case 0:
            return nil;

        case 1:
            return nil;
            
        case 2:
            return NSLocalizedString(@"Rescan blockchain if you think you may have missing transactions, "
                                     "or are having trouble sending (rescanning can take several minutes)", nil);
    }
    
    return nil;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: return (self.moreTx && indexPath.row >= self.transactions.count) ? 44.0 : TRANSACTION_CELL_HEIGHT;
        case 1: return 44.0;
        case 2: return 44.0;
    }
    
    return 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSString *sectionTitle = [self tableView:tableView titleForHeaderInSection:section];

    if (sectionTitle.length == 0) return 22.0;

    CGRect r = [sectionTitle boundingRectWithSize:CGSizeMake(self.view.frame.size.width - 20.0, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin
                attributes:@{NSFontAttributeName:[UIFont fontWithName:@"HelveticaNeue" size:13]} context:nil];
    
    return r.size.height + 22.0 + 10.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *l = [UILabel new];
    CGRect r = CGRectMake(15.0, 0.0, v.frame.size.width - 20.0, v.frame.size.height - 22.0);
    
    l.text = [self tableView:tableView titleForHeaderInSection:section];
    l.backgroundColor = [UIColor clearColor];
    l.font = [UIFont fontWithName:@"HelveticaNeue" size:13];
    l.textColor = [UIColor grayColor];
    l.shadowColor = [UIColor whiteColor];
    l.shadowOffset = CGSizeMake(0.0, 1.0);
    l.numberOfLines = 0;
    r.size.width = [l sizeThatFits:r.size].width;
    r.origin.x = (self.view.frame.size.width - r.size.width)/2;
    if (r.origin.x < 15.0) r.origin.x = 15.0;
    l.frame = r;
    v.backgroundColor = [UIColor clearColor];
    [v addSubview:l];

    return v;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return (section + 1 == [self numberOfSectionsInTableView:tableView]) ? 22.0 : 0.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForFooterInSection:section])];
    v.backgroundColor = [UIColor clearColor];
    return v;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //TODO: include an option to generate a new wallet and sweep old balance if backup may have been compromized
    UIViewController *destinationController = nil;

    switch (indexPath.section) {
        case 0: // transaction
            if (self.moreTx && indexPath.row >= self.transactions.count) { // more...
                [self performSelector:@selector(more:) withObject:tableView afterDelay:0.0];
            }
            else if (self.transactions.count > 0) [self showTx:self.transactions[indexPath.row]]; // transaction details

            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            break;

        case 1:
            switch (indexPath.row) {
                case 0: // buy bitcoin
                    [BREventManager saveEvent:@"tx_history:buy_btc"];
                    [tableView deselectRowAtIndexPath:indexPath animated:YES];
                    [self showBuy];
                    break;
                    
                case 1: // import private key
                    [BREventManager saveEvent:@"tx_history:import_priv_key"];
                    [self scanQR:nil];
                    break;

                case 2: // rescan blockchain
                    [[BRPeerManager sharedInstance] rescan];
                    [BREventManager saveEvent:@"tx_history:rescan"];
                    [self done:nil];
                    break;
            }

            break;

        case 2: // settings
            [BREventManager saveEvent:@"tx_history:settings"];
            destinationController = [self.storyboard instantiateViewControllerWithIdentifier:@"SettingsViewController"];
            [self.navigationController pushViewController:destinationController animated:YES];
            break;
    }
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) {
        [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:YES];
        return;
    }

    BRSeedViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"SeedViewController"];
    
    if (c.authSuccess) {
        [self.navigationController pushViewController:c animated:YES];
    }
    else [self.tableView deselectRowAtIndexPath:self.tableView.indexPathForSelectedRow animated:YES];
}

#pragma mark - UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return 0.35;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    UIView *containerView = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    BOOL pop = (to == self || (from != self && [to isKindOfClass:[BRSettingsViewController class]])) ? YES : NO;

    if (self.wallpaper.superview != containerView) [containerView insertSubview:self.wallpaper belowSubview:from.view];
    self.wallpaper.clipsToBounds = NO;
    to.view.center = CGPointMake(containerView.frame.size.width*(pop ? -1 : 3)/2, to.view.center.y);
    [containerView addSubview:to.view];

    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
    initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        to.view.center = from.view.center;
        from.view.center = CGPointMake(containerView.frame.size.width*(pop ? 3 : -1)/2, from.view.center.y);
        self.wallpaper.center = CGPointMake(self.wallpaper.frame.size.width/2 -
                                            containerView.frame.size.width*(pop ? 0 : 1)*PARALAX_RATIO,
                                            self.wallpaper.center.y);
    } completion:^(BOOL finished) {
        if (pop) [from.view removeFromSuperview];
        [transitionContext completeTransition:YES];
    }];
}

#pragma mark - UINavigationControllerDelegate

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC
toViewController:(UIViewController *)toVC
{
    return self;
}

#pragma mark - UIViewControllerTransitioningDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
{
    return self;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    return self;
}

@end
