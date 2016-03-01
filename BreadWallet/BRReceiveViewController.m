//
//  BRReceiveViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 5/8/13.
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

#import "BRReceiveViewController.h"
#import "BRRootViewController.h"
#import "BRPaymentRequest.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "BRTransaction.h"
#import "BRBubbleView.h"
#import "BRAppGroupConstants.h"
#import "UIImage+Utils.h"
#import "BREventManager.h"
#import <MobileCoreServices/UTCoreTypes.h>

#define QR_TIP      NSLocalizedString(@"Let others scan this QR code to get your bitcoin address. Anyone can send "\
                    "bitcoins to your wallet by transferring them to your address.", nil)
#define ADDRESS_TIP NSLocalizedString(@"This is your bitcoin address. Tap to copy it or send it by email or sms. The "\
                    "address will change each time you receive funds, but old addresses always work.", nil)

@interface BRReceiveViewController ()

@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, assign) BOOL showTips;
@property (nonatomic, strong) NSUserDefaults *groupDefs;
@property (nonatomic, strong) id balanceObserver, txStatusObserver;

@property (nonatomic, strong) IBOutlet UILabel *label;
@property (nonatomic, strong) IBOutlet UIButton *addressButton;
@property (nonatomic, strong) IBOutlet UIImageView *qrView;

@end

@implementation BRReceiveViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    BRWalletManager *manager = [BRWalletManager sharedInstance];
    BRPaymentRequest *req;

    self.groupDefs = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_ID];
    req = (_paymentRequest) ? _paymentRequest :
          [BRPaymentRequest requestWithString:[self.groupDefs stringForKey:APP_GROUP_RECEIVE_ADDRESS_KEY]];

    if (req.isValid) {
        self.qrView.image = [UIImage imageWithQRCodeData:req.data size:self.qrView.bounds.size
                             color:[CIColor colorWithRed:0.0 green:0.0 blue:0.0]];
        [self.addressButton setTitle:req.paymentAddress forState:UIControlStateNormal];
    }
    else [self.addressButton setTitle:nil forState:UIControlStateNormal];
    
    if (req.amount > 0) {
        self.label.text = [NSString stringWithFormat:@"%@ (%@)", [manager stringForAmount:req.amount],
                           [manager localCurrencyStringForAmount:req.amount]];
    }

    self.addressButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    [self updateAddress];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self hideTips];
    
    [super viewWillDisappear:animated];
}

- (void)dealloc
{
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (void)updateAddress
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BRWalletManager *manager = [BRWalletManager sharedInstance];
        BRPaymentRequest *req = self.paymentRequest;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.qrView.image = [UIImage imageWithQRCodeData:req.data size:self.qrView.bounds.size
                                 color:[CIColor colorWithRed:0.0 green:0.0 blue:0.0]];
            [self.addressButton setTitle:self.paymentAddress forState:UIControlStateNormal];
            
            if (req.amount > 0) {
                self.label.text = [NSString stringWithFormat:@"%@ (%@)", [manager stringForAmount:req.amount],
                                   [manager localCurrencyStringForAmount:req.amount]];
                
                if (! self.balanceObserver) {
                    self.balanceObserver =
                        [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
                            [self checkRequestStatus];
                        }];
                }
                
                if (! self.txStatusObserver) {
                    self.txStatusObserver =
                        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification
                        object:nil queue:nil usingBlock:^(NSNotification *note) {
                            [self checkRequestStatus];
                        }];
                }
            }
            else if (req.isValid) {
                [self.groupDefs setObject:req.data forKey:APP_GROUP_REQUEST_DATA_KEY];
                [self.groupDefs setObject:self.paymentAddress forKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
                [self.groupDefs synchronize];
            }
            else {
                [self.groupDefs removeObjectForKey:APP_GROUP_REQUEST_DATA_KEY];
                [self.groupDefs removeObjectForKey:APP_GROUP_RECEIVE_ADDRESS_KEY];
                [self.groupDefs synchronize];
            }
        });
    });
}

- (void)checkRequestStatus
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    BRPaymentRequest *req = self.paymentRequest;
    uint64_t total = 0, fuzz = [manager amountForLocalCurrencyString:[manager localCurrencyStringForAmount:1]]*2;
    
    if (! [manager.wallet addressIsUsed:self.paymentAddress]) return;

    for (BRTransaction *tx in manager.wallet.recentTransactions) {
        if ([tx.outputAddresses containsObject:self.paymentAddress]) continue;
        if (tx.blockHeight == TX_UNCONFIRMED &&
            [[BRPeerManager sharedInstance] relayCountForTransaction:tx.txHash] < PEER_MAX_CONNECTIONS) continue;
        total += [manager.wallet amountReceivedFromTransaction:tx];
                 
        if (total + fuzz >= req.amount) {
            UIView *view = self.navigationController.presentingViewController.view;

            [self done:nil];
            [view addSubview:[[[BRBubbleView viewWithText:[NSString
             stringWithFormat:NSLocalizedString(@"received %@ (%@)", nil), [manager stringForAmount:total],
             [manager localCurrencyStringForAmount:total]]
             center:CGPointMake(view.bounds.size.width/2, view.bounds.size.height/2)] popIn] popOutAfterDelay:3.0]];
            break;
        }
    }
}

- (BRPaymentRequest *)paymentRequest
{
    if (_paymentRequest) return _paymentRequest;
    return [BRPaymentRequest requestWithString:self.paymentAddress];
}

- (NSString *)paymentAddress
{
    if (_paymentRequest) return _paymentRequest.paymentAddress;
    return [BRWalletManager sharedInstance].wallet.receiveAddress;
}

- (BOOL)nextTip
{
    if (self.tipView.alpha < 0.5) return [(id)self.parentViewController.parentViewController nextTip];

    BRBubbleView *tipView = self.tipView;

    self.tipView = nil;
    [tipView popOut];

    if ([tipView.text hasPrefix:QR_TIP]) {
        self.tipView = [BRBubbleView viewWithText:ADDRESS_TIP tipPoint:[self.addressButton.superview
                        convertPoint:CGPointMake(self.addressButton.center.x, self.addressButton.center.y - 10.0)
                        toView:self.view] tipDirection:BRBubbleTipDirectionDown];
        self.tipView.backgroundColor = tipView.backgroundColor;
        self.tipView.font = tipView.font;
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips && [tipView.text hasPrefix:ADDRESS_TIP]) {
        self.showTips = NO;
        [(id)self.parentViewController.parentViewController tip:self];
    }

    return YES;
}

- (void)hideTips
{
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

#pragma mark - IBAction

- (IBAction)done:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)tip:(id)sender
{
    if ([self nextTip]) return;

    if (! [sender isKindOfClass:[UIGestureRecognizer class]] ||
        ([sender view] != self.qrView && ! [[sender view] isKindOfClass:[UILabel class]])) {
        if (! [sender isKindOfClass:[UIViewController class]]) return;
        self.showTips = YES;
    }

    self.tipView = [BRBubbleView viewWithText:QR_TIP
                    tipPoint:[self.qrView.superview convertPoint:self.qrView.center toView:self.view]
                    tipDirection:BRBubbleTipDirectionUp];
    self.tipView.backgroundColor = [UIColor orangeColor];
    self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
    [self.view addSubview:[self.tipView popIn]];
}

- (IBAction)address:(id)sender
{
    if ([self nextTip]) return;
    [BREventManager saveEvent:@"receive:address"];

    BOOL req = (_paymentRequest) ? YES : NO;
    UIActionSheet *actionSheet = [UIActionSheet new];

    actionSheet.title = [NSString stringWithFormat:NSLocalizedString(@"Receive bitcoins at this address: %@", nil),
               self.paymentAddress];
    actionSheet.delegate = self;
    [actionSheet addButtonWithTitle:(req) ? NSLocalizedString(@"copy request to clipboard", nil) :
     NSLocalizedString(@"copy address to clipboard", nil)];

    if ([MFMailComposeViewController canSendMail]) {
        [actionSheet addButtonWithTitle:(req) ? NSLocalizedString(@"send request as email", nil) :
         NSLocalizedString(@"send address as email", nil)];
    }

#if ! TARGET_IPHONE_SIMULATOR
    if ([MFMessageComposeViewController canSendText]) {
        [actionSheet addButtonWithTitle:(req) ? NSLocalizedString(@"send request as message", nil) :
         NSLocalizedString(@"send address as message", nil)];
    }
#endif

    if (! req) [actionSheet addButtonWithTitle:NSLocalizedString(@"request an amount", nil)];
    [actionSheet addButtonWithTitle:NSLocalizedString(@"cancel", nil)];
    actionSheet.cancelButtonIndex = actionSheet.numberOfButtons - 1;
    
    [actionSheet showInView:[UIApplication sharedApplication].keyWindow];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];

    //TODO: allow user to create a payment protocol request object, and use merge avoidance techniques:
    // https://medium.com/@octskyward/merge-avoidance-7f95a386692f
    
    if ([title isEqual:NSLocalizedString(@"copy address to clipboard", nil)] ||
        [title isEqual:NSLocalizedString(@"copy request to clipboard", nil)]) {
        [UIPasteboard generalPasteboard].string = (self.paymentRequest.amount > 0) ? self.paymentRequest.string :
                                                  self.paymentAddress;
        NSLog(@"\n\nCOPIED PAYMENT REQUEST/ADDRESS:\n\n%@", [UIPasteboard generalPasteboard].string);

        [self.view addSubview:[[[BRBubbleView viewWithText:NSLocalizedString(@"copied", nil)
         center:CGPointMake(self.view.bounds.size.width/2.0, self.view.bounds.size.height/2.0 - 130.0)] popIn]
         popOutAfterDelay:2.0]];
        [BREventManager saveEvent:@"receive:copy_address"];
    }
    else if ([title isEqual:NSLocalizedString(@"send address as email", nil)] ||
             [title isEqual:NSLocalizedString(@"send request as email", nil)]) {
        //TODO: implement BIP71 payment protocol mime attachement
        // https://github.com/bitcoin/bips/blob/master/bip-0071.mediawiki
        
        if ([MFMailComposeViewController canSendMail]) {
            MFMailComposeViewController *composeController = [MFMailComposeViewController new];
            
            composeController.subject = NSLocalizedString(@"Bitcoin address", nil);
            [composeController setMessageBody:self.paymentRequest.string isHTML:NO];
            [composeController addAttachmentData:UIImagePNGRepresentation(self.qrView.image) mimeType:@"image/png"
             fileName:@"qr.png"];
            composeController.mailComposeDelegate = self;
            [self.navigationController presentViewController:composeController animated:YES completion:nil];
            composeController.view.backgroundColor =
                [UIColor colorWithPatternImage:[UIImage imageNamed:@"wallpaper-default"]];
            [BREventManager saveEvent:@"receive:send_email"];
        }
        else {
            [BREventManager saveEvent:@"receive:email_not_configured"];
            [[[UIAlertView alloc] initWithTitle:@"" message:NSLocalizedString(@"email not configured", nil) delegate:nil
              cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        }
    }
    else if ([title isEqual:NSLocalizedString(@"send address as message", nil)] ||
             [title isEqual:NSLocalizedString(@"send request as message", nil)]) {
        if ([MFMessageComposeViewController canSendText]) {
            MFMessageComposeViewController *composeController = [MFMessageComposeViewController new];

            if ([MFMessageComposeViewController canSendSubject]) {
                composeController.subject = NSLocalizedString(@"Bitcoin address", nil);
            }
            
            composeController.body = self.paymentRequest.string;
            
            if ([MFMessageComposeViewController canSendAttachments]) {
                [composeController addAttachmentData:UIImagePNGRepresentation(self.qrView.image)
                 typeIdentifier:(NSString *)kUTTypePNG filename:@"qr.png"];
            }
            
            composeController.messageComposeDelegate = self;
            [self.navigationController presentViewController:composeController animated:YES completion:nil];
            composeController.view.backgroundColor = [UIColor colorWithPatternImage:
                                                      [UIImage imageNamed:@"wallpaper-default"]];
            [BREventManager saveEvent:@"receive:send_message"];
        }
        else {
            [BREventManager saveEvent:@"receive:message_not_configured"];
            [[[UIAlertView alloc] initWithTitle:@"" message:NSLocalizedString(@"sms not currently available", nil)
              delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        }
    }
    else if ([title isEqual:NSLocalizedString(@"request an amount", nil)]) {
        UINavigationController *amountNavController = [self.storyboard
                                                       instantiateViewControllerWithIdentifier:@"AmountNav"];
        
        ((BRAmountViewController *)amountNavController.topViewController).delegate = self;
        [self.navigationController presentViewController:amountNavController animated:YES completion:nil];
        [BREventManager saveEvent:@"receive:request_amount"];
    }
}

#pragma mark - MFMessageComposeViewControllerDelegate

- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
didFinishWithResult:(MessageComposeResult)result
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result
error:(NSError *)error
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - BRAmountViewControllerDelegate

- (void)amountViewController:(BRAmountViewController *)amountViewController selectedAmount:(uint64_t)amount
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    if (amount < TX_MIN_OUTPUT_AMOUNT) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"amount too small", nil)
          message:[NSString stringWithFormat:NSLocalizedString(@"bitcoin payments can't be less than %@", nil),
                   [manager stringForAmount:TX_MIN_OUTPUT_AMOUNT]]
          delegate:nil cancelButtonTitle:NSLocalizedString(@"ok", nil) otherButtonTitles:nil] show];
        [BREventManager saveEvent:@"receive:amount_too_small"];
        return;
    }

    [BREventManager saveEvent:@"receive:show_request"];
    UINavigationController *navController = (UINavigationController *)self.navigationController.presentedViewController;
    BRReceiveViewController *receiveController = [self.storyboard
                                                  instantiateViewControllerWithIdentifier:@"RequestViewController"];
    
    receiveController.paymentRequest = self.paymentRequest;
    receiveController.paymentRequest.amount = amount;
    receiveController.view.backgroundColor = self.parentViewController.parentViewController.view.backgroundColor;
    navController.delegate = receiveController;
    [navController pushViewController:receiveController animated:YES];
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

    [containerView addSubview:to.view];
    
    [UIView transitionFromView:from.view toView:to.view duration:[self transitionDuration:transitionContext]
    options:UIViewAnimationOptionTransitionFlipFromLeft completion:^(BOOL finished) {
        [from.view removeFromSuperview];
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
