//
//  BRRootViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 9/15/13.
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

#import "BRRootViewController.h"
#import "BRReceiveViewController.h"
#import "BRSendViewController.h"
#import "BRSettingsViewController.h"
#import "BRAppDelegate.h"
#import "BRBubbleView.h"
#import "BRBouncyBurgerButton.h"
#import "BRPeerManager.h"
#import "BRWalletManager.h"
#import "BRPaymentRequest.h"
#import "UIImage+Utils.h"
#import "BREventManager.h"
#import "Reachability.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>

#define BALANCE_TIP NSLocalizedString(@"This is your bitcoin balance. Bitcoin is a currency. "\
                                       "The exchange rate changes with the market.", nil)
#define BITS_TIP    NSLocalizedString(@"%@ is for 'bits'. %@ = 1 bitcoin.", nil)

#define BACKUP_DIALOG_TIME_KEY @"BACKUP_DIALOG_TIME"
#define BALANCE_KEY            @"BALANCE"
#define HAS_AUTHENTICATED_KEY  @"HAS_AUTHENTICATED"

@interface BRRootViewController ()

@property (nonatomic, strong) IBOutlet UIProgressView *progress, *pulse;
@property (nonatomic, strong) IBOutlet UILabel *percent;
@property (nonatomic, strong) IBOutlet UIView *errorBar, *splash, *logo, *blur;
@property (nonatomic, strong) IBOutlet UIGestureRecognizer *navBarTap;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *lock;
@property (nonatomic, strong) IBOutlet BRBouncyBurgerButton *burger;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *wallpaperXLeft;

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) BRBubbleView *tipView;
@property (nonatomic, assign) BOOL showTips, inNextTip, didAppear;
@property (nonatomic, assign) uint64_t balance;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSData *file;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) id urlObserver, fileObserver, foregroundObserver, backgroundObserver, balanceObserver;
@property (nonatomic, strong) id reachabilityObserver, syncStartedObserver, syncFinishedObserver, syncFailedObserver;
@property (nonatomic, strong) id activeObserver, resignActiveObserver, protectedObserver, seedObserver;
@property (nonatomic, assign) NSTimeInterval timeout, start;
@property (nonatomic, assign) SystemSoundID pingsound;

@end

@implementation BRRootViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    // detect jailbreak so we can throw up an idiot warning, in viewDidLoad so it can't easily be swizzled out
    struct stat s;
    BOOL jailbroken = (stat("/bin/sh", &s) == 0) ? YES : NO; // if we can see /bin/sh, the app isn't sandboxed

    // some anti-jailbreak detection tools re-sandbox apps, so do a secondary check for any MobileSubstrate dyld images
    for (uint32_t count = _dyld_image_count(), i = 0; i < count && ! jailbroken; i++) {
        if (strstr(_dyld_get_image_name(i), "MobileSubstrate")) jailbroken = YES;
    }

#if TARGET_IPHONE_SIMULATOR
    jailbroken = NO;
#endif

    _balance = UINT64_MAX;
    
    self.receiveViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"ReceiveViewController"];
    self.sendViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"SendViewController"];
    self.pageViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"PageViewController"];

    self.pageViewController.dataSource = self;
    [self.pageViewController setViewControllers:@[self.sendViewController]
     direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
    self.pageViewController.view.frame = self.view.bounds;
    [self addChildViewController:self.pageViewController];
    [self.view insertSubview:self.pageViewController.view belowSubview:self.splash];
    [self.pageViewController didMoveToParentViewController:self];

    for (UIView *view in self.pageViewController.view.subviews) {
        if (! [view isKindOfClass:[UIScrollView class]]) continue;
        self.scrollView = (id)view;
        self.scrollView.delegate = self;
        break;
    }

    BRWalletManager *manager = [BRWalletManager sharedInstance];

    self.urlObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRURLNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if (! manager.noWallet) {
                if (self.navigationController.topViewController != self) {
                    [self.navigationController popToRootViewControllerAnimated:YES];
                }
            
                if (self.navigationController.presentedViewController) {
                    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
                }
        
                BRSendViewController *c = self.sendViewController;
                
                [self.pageViewController setViewControllers:(c ? @[c] : @[])
                direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:^(BOOL finished) {
                    _url = note.userInfo[@"url"];
                    
                    if (self.didAppear && [UIApplication sharedApplication].protectedDataAvailable) {
                        _url = nil;
                        [c performSelector:@selector(handleURL:) withObject:note.userInfo[@"url"] afterDelay:0.0];
                    }
                }];
            }
        }];

    self.fileObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRFileNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if (! manager.noWallet) {
                if (self.navigationController.topViewController != self) {
                    [self.navigationController popToRootViewControllerAnimated:YES];
                }
            
                if (self.navigationController.presentedViewController) {
                    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
                }
                
                BRSendViewController *sendController = self.sendViewController;

                [self.pageViewController setViewControllers:(sendController ? @[sendController] : @[])
                direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:^(BOOL finished) {
                    _file = note.userInfo[@"file"];
                    
                    if (self.didAppear && [UIApplication sharedApplication].protectedDataAvailable) {
                        _file = nil;
                        [sendController handleFile:note.userInfo[@"file"]];
                    }
                }];
            }
        }];

    self.foregroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (! manager.noWallet) {
                BREventManager *eventMan = [BREventManager sharedEventManager];
                UIUserNotificationType types = UIUserNotificationTypeBadge;
                                               //| UIUserNotificationTypeSound | UIUserNotificationTypeAlert;
            
                [[BRPeerManager sharedInstance] connect];
                [self.sendViewController updateClipboardText];

                if (eventMan.isInSampleGroup && ! eventMan.hasAskedForPermission) {
                    [eventMan acquireUserPermissionInViewController:self.navigationController withCallback:nil];
                }
                else if ([UIUserNotificationSettings class] && // if iOS 8 or above
                         ([[UIApplication sharedApplication] currentUserNotificationSettings].types & types) != types) {
                    // register for notifications
                    [[UIApplication sharedApplication] registerUserNotificationSettings:[UIUserNotificationSettings
                     settingsForTypes:types categories:nil]];
                }
            }

            if (jailbroken && manager.wallet.balance > 0) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                  message:NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                            "Any 'jailbreak' app can access any other app's keychain data "
                                            "(and steal your bitcoins). "
                                            "Wipe this wallet immediately and restore on a secure device.", nil)
                 delegate:self cancelButtonTitle:NSLocalizedString(@"ignore", nil)
                 otherButtonTitles:NSLocalizedString(@"wipe", nil), nil] show];
            }
            else if (jailbroken) {
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
                  message:NSLocalizedString(@"DEVICE SECURITY COMPROMISED\n"
                                            "Any 'jailbreak' app can access any other app's keychain data "
                                            "(and steal your bitcoins).", nil)
                  delegate:self cancelButtonTitle:NSLocalizedString(@"ignore", nil)
                  otherButtonTitles:NSLocalizedString(@"close app", nil), nil] show];
            }
        }];

    self.backgroundObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (! manager.noWallet) { // lockdown the app
                manager.didAuthenticate = NO;
                self.navigationItem.titleView = self.logo;
                self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"burger"];
                self.navigationItem.rightBarButtonItem = self.lock;
                self.pageViewController.view.alpha = 1.0;
                [UIApplication sharedApplication].applicationIconBadgeNumber = 0; // reset app badge number
            }
        }];
    
    self.activeObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [self.blur removeFromSuperview];
            self.blur = nil;
        }];

    self.resignActiveObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            UIView *keyWindow = [UIApplication sharedApplication].keyWindow;
            UIImage *img;
            
            if (! [keyWindow viewWithTag:-411]) { // only take a screenshot if no views are marked highly sensitive
                UIGraphicsBeginImageContext([UIScreen mainScreen].bounds.size);
                [keyWindow drawViewHierarchyInRect:[UIScreen mainScreen].bounds afterScreenUpdates:NO];
                img = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            }
            else img = [UIImage imageNamed:@"wallpaper-default"];

            [self.blur removeFromSuperview];
            self.blur = [[UIImageView alloc] initWithImage:[img blurWithRadius:3]];
            [keyWindow.subviews.lastObject addSubview:self.blur];
        }];

    self.reachabilityObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:kReachabilityChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            if (! manager.noWallet && self.reachability.currentReachabilityStatus != NotReachable &&
                [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
                [[BRPeerManager sharedInstance] connect];
            }
            else if (! manager.noWallet && self.reachability.currentReachabilityStatus == NotReachable) {
                [self showErrorBar];
            }
        }];

    self.balanceObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletBalanceChangedNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            double progress = [BRPeerManager sharedInstance].syncProgress;
        
            if (_balance != UINT64_MAX && progress > DBL_EPSILON && progress + DBL_EPSILON < 1.0) { // wait for sync
                self.balance = _balance; // this updates the local currency value with the latest exchange rate
                return;
            }
            
            [self showBackupDialogIfNeeded];
            [self.receiveViewController updateAddress];
            self.balance = manager.wallet.balance;
        }];

    self.seedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRWalletManagerSeedChangedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            [self.receiveViewController updateAddress];
            self.balance = manager.wallet.balance;
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:HAS_AUTHENTICATED_KEY];
        }];

    self.syncStartedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncStartedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.reachability.currentReachabilityStatus == NotReachable) return;
            [self hideErrorBar];
            [self startActivityWithTimeout:0];
        }];
    
    self.syncFinishedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFinishedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.timeout < 1.0) [self stopActivityWithSuccess:YES];
            [self showBackupDialogIfNeeded];
            if (! self.percent.hidden) [self hideTips];
            self.percent.hidden = YES;
            if (! manager.didAuthenticate) self.navigationItem.titleView = self.logo;
            [self.receiveViewController updateAddress];
            self.balance = manager.wallet.balance;
        }];
    
    self.syncFailedObserver =
        [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerSyncFailedNotification object:nil
        queue:nil usingBlock:^(NSNotification *note) {
            if (self.timeout < 1.0) [self stopActivityWithSuccess:YES];
            [self showBackupDialogIfNeeded];
            [self.receiveViewController updateAddress];
            [self showErrorBar];
        }];
    
    self.reachability = [Reachability reachabilityForInternetConnection];
    [self.reachability startNotifier];
    
    self.navigationController.delegate = self;

#if BITCOIN_TESTNET
    UILabel *label = [UILabel new];

    label.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:13.0];
    label.textColor = [UIColor redColor];
    label.textAlignment = NSTextAlignmentRight;
    label.text = @"testnet";
    label.tag = 0xbeef;
    [label sizeToFit];
    label.center = CGPointMake(self.view.frame.size.width - label.frame.size.width,
                               self.view.frame.size.height - (label.frame.size.height + 5));
    [self.view addSubview:label];
#endif

#if SNAPSHOT
    [self.view viewWithTag:0xbeef].hidden = YES;
    [self.navigationController
     presentViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"] animated:NO
     completion:^{
        [self.navigationController.presentedViewController.view
         addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nextScreen:)]];
     }];
#endif

    if (manager.watchOnly) { // watch only wallet
        UILabel *label = [UILabel new];
        
        label.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:13.0];
        label.textColor = [UIColor redColor];
        label.textAlignment = NSTextAlignmentRight;
        label.text = @"watch only";
        [label sizeToFit];
        label.center = CGPointMake(self.view.frame.size.width - label.frame.size.width,
                                   self.view.frame.size.height - (label.frame.size.height + 5)*2);
        [self.view addSubview:label];
    }

    AudioServicesCreateSystemSoundID((__bridge CFURLRef)[[NSBundle mainBundle] URLForResource:@"coinflip"
                                                         withExtension:@"aiff"], &_pingsound);

    if (! manager.noWallet) {
        //TODO: do some kickass quick logo animation, fast circle spin that slows
        self.splash.hidden = YES;
        self.navigationController.navigationBar.hidden = NO;
        [[UIApplication sharedApplication] setStatusBarHidden:NO];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"burger"];
    self.pageViewController.view.alpha = 1.0;
    if ([BRWalletManager sharedInstance].didAuthenticate) [self unlock:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    self.didAppear = YES;
    
    if (! self.navBarTap) {
        self.navBarTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(navBarTap:)];
        [self.navigationController.navigationBar addGestureRecognizer:self.navBarTap];
    }

    if (! self.protectedObserver) {
        self.protectedObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
            object:nil queue:nil usingBlock:^(NSNotification *note) {
                [self performSelector:@selector(protectedViewDidAppear) withObject:nil afterDelay:0.0];
            }];
    }

    if ([UIApplication sharedApplication].protectedDataAvailable) {
        [self performSelector:@selector(protectedViewDidAppear) withObject:nil afterDelay:0.0];
    }
    
    [super viewDidAppear:animated];
}

- (void)protectedViewDidAppear
{
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    BRWalletManager *manager = [BRWalletManager sharedInstance];

    if (self.protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    self.protectedObserver = nil;

    if ([defs integerForKey:SETTINGS_MAX_DIGITS_KEY] == 5) {
        manager.format.currencySymbol = @"m" BTC NARROW_NBSP;
        manager.format.maximumFractionDigits = 5;
        manager.format.maximum = @((MAX_MONEY/SATOSHIS)*1000);
    }
    else if ([defs integerForKey:SETTINGS_MAX_DIGITS_KEY] == 8) {
        manager.format.currencySymbol = BTC NARROW_NBSP;
        manager.format.maximumFractionDigits = 8;
        manager.format.maximum = @(MAX_MONEY/SATOSHIS);
    }
    
    if (manager.noWallet) {
        if (! manager.passcodeEnabled) {
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"turn device passcode on", nil)
              message:NSLocalizedString(@"\nA device passcode is needed to safeguard your wallet. Go to settings and "
                                        "turn passcode on to continue.", nil)
              delegate:self cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"close app", nil), nil] show];
        }
        else {
            [self.navigationController
            presentViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"] animated:NO
            completion:^{
                self.splash.hidden = YES;
                self.navigationController.navigationBar.hidden = NO;
                [self.pageViewController setViewControllers:@[self.receiveViewController]
                 direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
            }];

            manager.didAuthenticate = YES;
            self.showTips = YES;
            [self unlock:nil];
        }
    }
    else {
        if (_balance == UINT64_MAX && [defs objectForKey:BALANCE_KEY]) self.balance = [defs doubleForKey:BALANCE_KEY];
        self.splash.hidden = YES;
        self.navigationController.navigationBar.hidden = NO;
        self.pageViewController.view.alpha = 1.0;
        [self.receiveViewController updateAddress];
        if (self.reachability.currentReachabilityStatus == NotReachable) [self showErrorBar];

        if (self.navigationController.visibleViewController == self) {
            [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
            [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
        }

#if SNAPSHOT
        return;
#endif

        if (! [defs boolForKey:HAS_AUTHENTICATED_KEY]) {
            while (! [manager authenticateWithPrompt:nil andTouchId:NO]) { }
            [defs setBool:YES forKey:HAS_AUTHENTICATED_KEY];
            [self unlock:nil];
        }

        if (self.navigationController.visibleViewController == self) {
            if (self.showTips) [self performSelector:@selector(tip:) withObject:nil afterDelay:0.3];
        }
        
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
            [[BRPeerManager sharedInstance] connect];
            [UIApplication sharedApplication].applicationIconBadgeNumber = 0; // reset app badge number
            
            if (self.url) [self.sendViewController handleURL:self.url], self.url = nil;
            if (self.file) [self.sendViewController handleFile:self.file], self.file = nil;
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (self.navBarTap) [self.navigationController.navigationBar removeGestureRecognizer:self.navBarTap];
    self.navBarTap = nil;
    [self hideTips];

    [super viewWillDisappear:animated];
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender
{
    if ([self nextTip]) return NO;

    return YES;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    [super prepareForSegue:segue sender:sender];

    [segue.destinationViewController setTransitioningDelegate:self];
    [segue.destinationViewController setModalPresentationStyle:UIModalPresentationCustom];
    [self hideErrorBar];
    
    if (sender == self) { // show recovery phrase
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"WARNING", nil)
          message:NSLocalizedString(@"\nDO NOT let anyone see your recovery phrase or they can spend your bitcoins.\n\n"
                                    "NEVER type your recovery phrase into password managers or elsewhere. Other "
                                    "devices may be infected.\n", nil)
          delegate:[(id)segue.destinationViewController viewControllers].firstObject
          cancelButtonTitle:NSLocalizedString(@"cancel", nil) otherButtonTitles:NSLocalizedString(@"show", nil), nil]
         show];
    }
}

- (void)viewDidLayoutSubviews
{
    [self scrollViewDidScroll:self.scrollView];
}

- (void)dealloc
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self.reachability stopNotifier];
    if (self.navigationController.delegate == self) self.navigationController.delegate = nil;
    if (self.urlObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.urlObserver];
    if (self.fileObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.fileObserver];
    if (self.protectedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.protectedObserver];
    if (self.foregroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.foregroundObserver];
    if (self.backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.backgroundObserver];
    if (self.activeObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.activeObserver];
    if (self.resignActiveObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.resignActiveObserver];
    if (self.reachabilityObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.reachabilityObserver];
    if (self.balanceObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.balanceObserver];
    if (self.seedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.seedObserver];
    if (self.syncStartedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncStartedObserver];
    if (self.syncFinishedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFinishedObserver];
    if (self.syncFailedObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.syncFailedObserver];
    AudioServicesDisposeSystemSoundID(self.pingsound);
}

- (void)setBalance:(uint64_t)balance
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];

    if (balance > _balance && [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        [self.view addSubview:[[[BRBubbleView viewWithText:[NSString
         stringWithFormat:NSLocalizedString(@"received %@ (%@)", nil), [manager stringForAmount:balance - _balance],
                          [manager localCurrencyStringForAmount:balance - _balance]]
         center:CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2)] popIn]
         popOutAfterDelay:3.0]];
        [self ping];
    }

    _balance = balance;

    // use setDouble since setInteger won't hold a uint64_t
    [[NSUserDefaults standardUserDefaults] setDouble:balance forKey:BALANCE_KEY];

    if (self.percent.hidden) {
        self.navigationItem.title = [NSString stringWithFormat:@"%@ (%@)", [manager stringForAmount:balance],
                                     [manager localCurrencyStringForAmount:balance]];
    }
}

- (void)showSyncing
{
    double progress = [BRPeerManager sharedInstance].syncProgress;

    if (progress > DBL_EPSILON && progress + DBL_EPSILON < 1.0 &&
        [BRWalletManager sharedInstance].seedCreationTime + 60*60*24 < [NSDate timeIntervalSinceReferenceDate]) {
        self.percent.hidden = NO;
        self.navigationItem.titleView = nil;
        self.navigationItem.title = NSLocalizedString(@"syncing...", nil);
    }
}

- (void)startActivityWithTimeout:(NSTimeInterval)timeout
{
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];

    if (timeout > 1 && start + timeout > self.start + self.timeout) {
        self.timeout = timeout;
        self.start = start;
    }

    if (timeout <= DBL_EPSILON) {
        if ([[BRPeerManager sharedInstance] timestampForBlockHeight:[BRPeerManager sharedInstance].lastBlockHeight] +
            60*60*24*7 < [NSDate timeIntervalSinceReferenceDate]) {
            if ([BRWalletManager sharedInstance].seedCreationTime + 60*60*24 < start) {
                self.percent.hidden = NO;
                self.navigationItem.titleView = nil;
                self.navigationItem.title = NSLocalizedString(@"syncing...", nil);
            }
        }
        else [self performSelector:@selector(showSyncing) withObject:nil afterDelay:5.0];
    }

    [UIApplication sharedApplication].idleTimerDisabled = YES;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    self.progress.hidden = self.pulse.hidden = NO;
    [UIView animateWithDuration:0.2 animations:^{ self.progress.alpha = 1.0; }];
    [self updateProgress];
}

- (void)stopActivityWithSuccess:(BOOL)success
{
    double progress = [BRPeerManager sharedInstance].syncProgress;

    self.start = self.timeout = 0.0;
    if (progress > DBL_EPSILON && progress + DBL_EPSILON < 1.0) return; // not done syncing
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    if (self.progress.alpha < 0.5) return;

    if (success) {
        [self.progress setProgress:1.0 animated:YES];
        [self.pulse setProgress:1.0 animated:YES];
        
        [UIView animateWithDuration:0.2 animations:^{
            self.progress.alpha = self.pulse.alpha = 0.0;
        } completion:^(BOOL finished) {
            self.progress.hidden = self.pulse.hidden = YES;
            self.progress.progress = self.pulse.progress = 0.0;
        }];
    }
    else {
        self.progress.hidden = self.pulse.hidden = YES;
        self.progress.progress = self.pulse.progress = 0.0;
    }
}

- (void)setProgressTo:(NSNumber *)n
{
    self.progress.progress = n.floatValue;
}

- (void)updateProgress
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateProgress) object:nil];

    static int counter = 0;
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - self.start;
    double progress = [BRPeerManager sharedInstance].syncProgress;

    if (progress > DBL_EPSILON && ! self.percent.hidden && self.tipView.alpha > 0.5) {
        self.tipView.text = [NSString stringWithFormat:NSLocalizedString(@"block #%d of %d", nil),
                             [BRPeerManager sharedInstance].lastBlockHeight,
                             [BRPeerManager sharedInstance].estimatedBlockHeight];
    }

    if (self.timeout > 1.0 && 0.1 + 0.9*elapsed/self.timeout < progress) progress = 0.1 + 0.9*elapsed/self.timeout;
    if (progress <= DBL_EPSILON) progress = self.progress.progress;

    if ((counter % 13) == 0) {
        self.pulse.alpha = 1.0;
        [self.pulse setProgress:progress animated:progress > self.pulse.progress];
        [self.progress setProgress:progress animated:progress > self.progress.progress];

        if (progress > self.progress.progress) {
            [self performSelector:@selector(setProgressTo:) withObject:@(progress) afterDelay:1.0];
        }
        else self.progress.progress = progress;
        
        [UIView animateWithDuration:1.59 delay:1.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            self.pulse.alpha = 0.0;
        } completion:nil];

        [self.pulse performSelector:@selector(setProgress:) withObject:nil afterDelay:2.59];
    }
    else if ((counter % 13) >= 5) {
        [self.progress setProgress:progress animated:progress > self.progress.progress];
        [self.pulse setProgress:progress animated:progress > self.pulse.progress];
    }

    counter++;
    self.percent.text = [NSString stringWithFormat:@"%0.1f%%", (progress > 0.1 ? progress - 0.1 : 0.0)*111.0];

    if (progress + DBL_EPSILON >= 1.0) {
        if (self.timeout < 1.0) [self stopActivityWithSuccess:YES];
        if (! self.percent.hidden) [self hideTips];
        self.percent.hidden = YES;
        if (! [BRWalletManager sharedInstance].didAuthenticate) self.navigationItem.titleView = self.logo;
    }
    else [self performSelector:@selector(updateProgress) withObject:nil afterDelay:0.2];
}

- (void)ping
{
     AudioServicesPlaySystemSound(self.pingsound);
}

- (void)showErrorBar
{
    if (self.navigationItem.prompt != nil || self.navigationController.presentedViewController != nil) return;
    self.navigationItem.prompt = @"";
    self.errorBar.hidden = NO;
    self.errorBar.alpha = 0.0;
    
    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration delay:0.0
    options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.burger.center = CGPointMake(self.burger.center.x, 70.0);
        self.errorBar.alpha = 1.0;
    } completion:nil];
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    if (! self.percent.hidden) [self hideTips];
    self.percent.hidden = YES;
    if (! manager.didAuthenticate) self.navigationItem.titleView = self.logo;
    self.balance = _balance; // reset navbar title
    self.progress.hidden = self.pulse.hidden = YES;
}

- (void)hideErrorBar
{
    if (self.navigationItem.prompt == nil) return;
    self.navigationItem.prompt = nil;

    [UIView animateWithDuration:UINavigationControllerHideShowBarDuration delay:0.0
    options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.burger.center = CGPointMake(self.burger.center.x, 40.0);
        self.errorBar.alpha = 0.0;
    } completion:^(BOOL finished) {
        if (self.navigationItem.prompt == nil) self.errorBar.hidden = YES;
    }];
}

- (void)showBackupDialogIfNeeded
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (self.navigationController.visibleViewController != self || ! [defs boolForKey:WALLET_NEEDS_BACKUP_KEY] ||
        manager.wallet.balance == 0 || [defs doubleForKey:BACKUP_DIALOG_TIME_KEY] > now - 36*60*60) return;
    
    BOOL first = ([defs doubleForKey:BACKUP_DIALOG_TIME_KEY] < 1.0) ? YES : NO;
    
    [defs setDouble:now forKey:BACKUP_DIALOG_TIME_KEY];
    
    [[[UIAlertView alloc]
      initWithTitle:(first) ? NSLocalizedString(@"you received bitcoin!", nil) : NSLocalizedString(@"IMPORTANT", nil)
      message:[NSString stringWithFormat:NSLocalizedString(@"\n%@\n\nif you ever lose your phone, you will need it to "
                                                           "recover your wallet", nil),
               (first) ? NSLocalizedString(@"next, write down your recovery phrase", nil) :
               NSLocalizedString(@"WRITE DOWN YOUR RECOVERY PHRASE", nil)] delegate:self
      cancelButtonTitle:NSLocalizedString(@"do it later", nil)
      otherButtonTitles:NSLocalizedString(@"show phrase", nil), nil] show];
}

- (void)hideTips
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(tip:) object:nil];
    if (self.tipView.alpha > 0.5) [self.tipView popOut];
}

- (BOOL)nextTip
{
    if (self.tipView.alpha < 0.5) { // if the tip view is dismissed, cycle through child view controller tips
        BOOL ret;

        if (self.inNextTip) return NO; // break out of recursive loop
        self.inNextTip = YES;
        ret = [self.pageViewController.viewControllers.lastObject nextTip];
        self.inNextTip = NO;
        return ret;
    }

    BRBubbleView *tipView = self.tipView;

    self.tipView = nil;
    [tipView popOut];

    if ([tipView.text hasPrefix:BALANCE_TIP]) {
        BRWalletManager *manager = [BRWalletManager sharedInstance];
        UINavigationBar *navBar = self.navigationController.navigationBar;
        NSString *text = [NSString stringWithFormat:BITS_TIP,
                          manager.format.currencySymbol, [manager stringForAmount:SATOSHIS]];
        CGRect r = [self.navigationItem.title boundingRectWithSize:navBar.bounds.size options:0
                    attributes:navBar.titleTextAttributes context:nil];

        self.tipView = [BRBubbleView viewWithText:text
                        tipPoint:CGPointMake(navBar.center.x + 5.0 - r.size.width/2.0,
                                             navBar.frame.origin.y + navBar.frame.size.height - 10)
                        tipDirection:BRBubbleTipDirectionUp];
        self.tipView.backgroundColor = tipView.backgroundColor;
        self.tipView.font = tipView.font;
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
    }
    else if (self.showTips) {
        self.showTips = NO;
        [self.pageViewController.viewControllers.lastObject tip:self];
    }

    return YES;
}

#pragma mark - IBAction

- (IBAction)tip:(id)sender
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    if (sender == self.receiveViewController) {
        BRSendViewController *sendController = self.sendViewController;

        [(id)self.pageViewController setViewControllers:@[sendController]
         direction:UIPageViewControllerNavigationDirectionReverse animated:YES
         completion:^(BOOL finished) { [sendController tip:sender]; }];
    }
    else if (sender == self.sendViewController) {
        self.scrollView.scrollEnabled = YES;
        [(id)self.pageViewController setViewControllers:@[self.receiveViewController]
         direction:UIPageViewControllerNavigationDirectionForward animated:YES completion:nil];
    }
    else if (self.showTips && manager.seedCreationTime + 60*60*24 < [NSDate timeIntervalSinceReferenceDate]) {
        self.showTips = NO;
    }
    else {
        UINavigationBar *bar = self.navigationController.navigationBar;
        NSString *tip = (self.percent.hidden) ? BALANCE_TIP :
                        [NSString stringWithFormat:NSLocalizedString(@"block #%d of %d", nil),
                        [BRPeerManager sharedInstance].lastBlockHeight,
                        [BRPeerManager sharedInstance].estimatedBlockHeight];

        self.tipView = [BRBubbleView viewWithText:tip
                        tipPoint:CGPointMake(bar.center.x, bar.frame.origin.y + bar.frame.size.height - 10)
                        tipDirection:BRBubbleTipDirectionUp];
        self.tipView.backgroundColor = [UIColor orangeColor];
        self.tipView.font = [UIFont fontWithName:@"HelveticaNeue" size:15.0];
        self.tipView.userInteractionEnabled = NO;
        [self.view addSubview:[self.tipView popIn]];
        if (self.showTips) self.scrollView.scrollEnabled = NO;
    }
}

- (IBAction)unlock:(id)sender
{
    [BREventManager saveEvent:@"root:unlock"];
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    if (sender && ! manager.didAuthenticate && ! [manager authenticateWithPrompt:nil andTouchId:YES]) return;
    [BREventManager saveEvent:@"root:unlock_success"];
    
    self.navigationItem.titleView = nil;
    [self.navigationItem setRightBarButtonItem:nil animated:(sender) ? YES : NO];
}

- (IBAction)connect:(id)sender
{
    [BREventManager saveEvent:@"root:connect"];
    if (! sender && [self.reachability currentReachabilityStatus] == NotReachable) return;

    [[BRPeerManager sharedInstance] connect];
    [BREventManager saveEvent:@"root:connect_success"];
}

- (IBAction)navBarTap:(id)sender
{
    if ([self nextTip]) return;

    if (! self.errorBar.hidden) {
        [self connect:sender];
    }
    else if (! [BRWalletManager sharedInstance].didAuthenticate && self.percent.hidden) {
        [self unlock:sender];
    }
    else [self tip:sender];
}

#if SNAPSHOT
- (IBAction)nextScreen:(id)sender
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    if (self.navigationController.presentedViewController) {
        if (manager.noWallet) [manager generateRandomSeed];
        self.showTips = NO;
        [self.navigationController dismissViewControllerAnimated:NO completion:^{
            manager.didAuthenticate = NO;
            self.navigationItem.titleView = self.logo;
            self.navigationItem.rightBarButtonItem = self.lock;
            self.pageViewController.view.alpha = 1.0;
            self.navigationController.navigationBar.hidden = YES;
            [[UIApplication sharedApplication] setStatusBarHidden:YES];
            self.splash.hidden = NO;
            [self.splash
             addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nextScreen:)]];
        }];
    }
    else if (! self.splash.hidden) {
        self.navigationController.navigationBar.hidden = NO;
        [[UIApplication sharedApplication] setStatusBarHidden:NO];
        self.splash.hidden = YES;
        [self stopActivityWithSuccess:YES];
        [self.pageViewController setViewControllers:@[self.receiveViewController]
         direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:nil];
        self.receiveViewController.paymentRequest =
            [BRPaymentRequest requestWithString:@"n2eMqTT929pb1RDNuqEnxdaLau1rxy3efi"];
        [self.receiveViewController updateAddress];
        [self.progress removeFromSuperview];
        [self.pulse removeFromSuperview];
    }
}
#endif

#pragma mark - UIPageViewControllerDataSource

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController
viewControllerBeforeViewController:(UIViewController *)viewController
{
    return (viewController == self.receiveViewController) ? self.sendViewController : nil;
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController
viewControllerAfterViewController:(UIViewController *)viewController
{
    return (viewController == self.sendViewController) ? self.receiveViewController : nil;
}

- (NSInteger)presentationCountForPageViewController:(UIPageViewController *)pageViewController
{
    return 2;
}

- (NSInteger)presentationIndexForPageViewController:(UIPageViewController *)pageViewController
{
    return (pageViewController.viewControllers.lastObject == self.receiveViewController) ? 1 : 0;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat off = scrollView.contentOffset.x + (scrollView.contentInset.left < 0 ? scrollView.contentInset.left : 0);
    
    self.wallpaperXLeft.constant = -PARALAX_RATIO*off;
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == alertView.cancelButtonIndex) return;

    if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:NSLocalizedString(@"close app", nil)]) abort();

    if ([[alertView buttonTitleAtIndex:buttonIndex] isEqual:NSLocalizedString(@"wipe", nil)]) {
        [[[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"CONFIRM WIPE", nil) delegate:self
          cancelButtonTitle:NSLocalizedString(@"cancel", nil) destructiveButtonTitle:NSLocalizedString(@"wipe", nil)
          otherButtonTitles:nil] showInView:[UIApplication sharedApplication].keyWindow];
        return;
    }
    
    [self performSegueWithIdentifier:@"SettingsSegue" sender:self];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != actionSheet.destructiveButtonIndex) return;

    [[BRWalletManager sharedInstance] setSeedPhrase:nil];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:WALLET_NEEDS_BACKUP_KEY];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UINavigationController *newWalletNavController
        = [self.storyboard instantiateViewControllerWithIdentifier:@"NewWalletNav"];

    [self.navigationController presentViewController:newWalletNavController animated:NO completion:nil];

    [[[UIAlertView alloc] initWithTitle:@"" message:NSLocalizedString(@"the app will now close", nil) delegate:self
      cancelButtonTitle:nil otherButtonTitles:NSLocalizedString(@"close app", nil), nil] show];
}

#pragma mark - UIViewControllerAnimatedTransitioning

// This is used for percent driven interactive transitions, as well as for container controllers that have companion
// animations that might need to synchronize with the main animation.
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext
{
    return (transitionContext.isAnimated) ? 0.35 : 0.0;
}

// This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext
{
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    UIView *containerView = transitionContext.containerView;
    UIViewController *to = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey],
                     *from = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];

    if (to == self || from == self) { // nav stack push/pop
        self.progress.hidden = self.pulse.hidden = YES;
        [containerView addSubview:to.view];
        to.view.center = CGPointMake(containerView.frame.size.width*(to == self ? -1 : 3)/2, to.view.center.y);

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            to.view.center = from.view.center;
            from.view.center = CGPointMake(containerView.frame.size.width*(to == self ? 3 : -1)/2, from.view.center.y);
            self.wallpaperXLeft.constant = containerView.frame.size.width*(to == self ? 0 : -1)*PARALAX_RATIO;
        } completion:^(BOOL finished) {
            if (to == self) {
                [from.view removeFromSuperview];
                self.navigationController.navigationBarHidden = YES; // hack to fix topLayoutGuide bug
                [self.navigationController performSelector:@selector(setNavigationBarHidden:) withObject:nil
                 afterDelay:0];
            }

            if (self.progress.progress > 0) self.progress.hidden = self.pulse.hidden = NO;
            [transitionContext completeTransition:YES];
        }];
    }
    else if ([to isKindOfClass:[UINavigationController class]] && from == self.navigationController) { // modal display
        // to.view must be added to superview prior to positioning it off screen for its navbar to underlap statusbar
        [self.navigationController.navigationBar.superview insertSubview:to.view
                                                            belowSubview:self.navigationController.navigationBar];
        [containerView layoutIfNeeded];
        to.view.center = CGPointMake(to.view.center.x, containerView.frame.size.height*3/2);

        UINavigationItem *item = [(id)to topViewController].navigationItem;
        UIView *titleView = item.titleView;
        UIBarButtonItem *rightButton = item.rightBarButtonItem;

        item.title = nil;
        item.leftBarButtonItem.image = [UIImage imageNamed:@"none"];
        item.titleView = nil;
        item.rightBarButtonItem = nil;
        self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"none"];
        [containerView addSubview:self.burger];
        [containerView layoutIfNeeded];
        self.burger.center = CGPointMake(26.0, 40.0);
        self.burger.hidden = NO;
        [self.burger setX:YES completion:nil];

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            to.view.center = CGPointMake(to.view.center.x, containerView.frame.size.height/2);
            self.pageViewController.view.alpha = 0.0;
            self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                              containerView.frame.size.height/4.0);
        } completion:^(BOOL finished) {
            self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                              containerView.frame.size.height/2.0);
            
            if (! manager.didAuthenticate) {
                item.rightBarButtonItem = rightButton;
                if (self.percent.hidden) item.titleView = titleView;
            }
            
            item.title = self.navigationItem.title;
            item.leftBarButtonItem.image = [UIImage imageNamed:@"x"];
            [containerView addSubview:to.view];
            [transitionContext completeTransition:YES];
        }];
    }
    else if ([from isKindOfClass:[UINavigationController class]] && to == self.navigationController) { // modal dismiss
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
            [[BRPeerManager sharedInstance] connect];
            [self.sendViewController updateClipboardText];
        }
        
        if (manager.didAuthenticate) [self unlock:nil];
        [self.navigationController.navigationBar.superview insertSubview:from.view
         belowSubview:self.navigationController.navigationBar];
        
        UINavigationItem *item = [(id)from topViewController].navigationItem;
        UIView *titleView = item.titleView;
        UIBarButtonItem *rightButton = item.rightBarButtonItem;

        item.title = nil;
        item.leftBarButtonItem.image = [UIImage imageNamed:@"none"];
        item.titleView = nil;
        item.rightBarButtonItem = nil;
        self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"none"];
        self.burger.hidden = NO;
        [containerView layoutIfNeeded];
        self.burger.center = CGPointMake(26.0, 40.0);
        [self.burger setX:NO completion:nil];
        self.pageViewController.view.alpha = 0.0;
        self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                          containerView.frame.size.height/4.0);

        [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0.0 usingSpringWithDamping:0.8
        initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            from.view.center = CGPointMake(from.view.center.x, containerView.frame.size.height*3/2);
            self.pageViewController.view.alpha = 1.0;
            self.pageViewController.view.center = CGPointMake(self.pageViewController.view.center.x,
                                                              containerView.frame.size.height/2);
        } completion:^(BOOL finished) {
            item.rightBarButtonItem = rightButton;
            item.titleView = titleView;
            item.title = self.navigationItem.title;
            item.leftBarButtonItem.image = [UIImage imageNamed:@"x"];
            [from.view removeFromSuperview];
            self.burger.hidden = YES;
            self.navigationItem.leftBarButtonItem.image = [UIImage imageNamed:@"burger"];
            [transitionContext completeTransition:YES];
            if (self.reachability.currentReachabilityStatus == NotReachable) [self showErrorBar];
        }];
    }
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
