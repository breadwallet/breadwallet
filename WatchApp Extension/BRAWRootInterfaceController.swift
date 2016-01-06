//
//  BRAWRootInterfaceController.swift
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

import WatchKit

class BRAWRootInterfaceController: WKInterfaceController {
    @IBOutlet var setupWalletMessageLabel: WKInterfaceLabel! {
        didSet{
            setupWalletMessageLabel.setHidden(true)
        }
    }
    @IBOutlet var loadingIndicator: WKInterfaceGroup!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
        updateUI()
        NSNotificationCenter.defaultCenter().addObserver(
            self, selector: "updateUI", name: BRAWWatchDataManager.WalletStatusDidChangeNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(
            self, selector: "txReceive:", name: BRAWWatchDataManager.WalletTxReceiveNotification, object: nil)
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func updateUI() {
        switch BRAWWatchDataManager.sharedInstance.walletStatus {
        case .Unknown:
            loadingIndicator.setHidden(false)
            setupWalletMessageLabel.setHidden(true)
        case .NotSetup:
            loadingIndicator.setHidden(true)
            setupWalletMessageLabel.setHidden(false)
        case .HasSetup:
            WKInterfaceController.reloadRootControllersWithNames(
                ["BRAWBalanceInterfaceController","BRAWReceiveMoneyInterfaceController"], contexts: [])
        }
    }
    
    @objc func txReceive(notification: NSNotification?) {
        print("root view controller received notification: \(notification)")
        if let userData = notification?.userInfo,
            noteString = userData[NSLocalizedDescriptionKey] as? String {
                self.presentAlertControllerWithTitle(
                    noteString, message: nil, preferredStyle: .Alert, actions: [
                        WKAlertAction(title: NSLocalizedString("OK", comment: ""),
                            style: .Cancel, handler: { self.dismissController() })])
        }
    }
}
