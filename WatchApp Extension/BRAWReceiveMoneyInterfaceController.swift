//
//  BRAWReceiveMoneyInterfaceController.swift
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
import WatchConnectivity

class BRAWReceiveMoneyInterfaceController: WKInterfaceController, WCSessionDelegate, BRAWKeypadDelegate {

    @IBOutlet var loadingIndicator: WKInterfaceGroup!
    @IBOutlet var imageContainer: WKInterfaceGroup!
    @IBOutlet var qrCodeImage: WKInterfaceImage!
    @IBOutlet var qrCodeButton: WKInterfaceButton!
    var customQR: UIImage?
    
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
    }

    override func willActivate() {
        super.willActivate()
        customQR = nil
        updateReceiveUI()
        NSNotificationCenter.defaultCenter().addObserver(
            self, selector: "updateReceiveUI",
            name: BRAWWatchDataManager.ApplicationDataDidUpdateNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(
            self, selector: "txReceive:", name: BRAWWatchDataManager.WalletTxReceiveNotification, object: nil)
    }

    override func didDeactivate() {
        super.didDeactivate()
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    @objc func txReceive(notification: NSNotification?) {
        print("receive view controller received notification: \(notification)")
        if let userData = notification?.userInfo,
            noteString = userData[NSLocalizedDescriptionKey] as? String {
                self.presentAlertControllerWithTitle(
                    noteString, message: nil, preferredStyle: .Alert, actions: [
                        WKAlertAction(title: NSLocalizedString("OK", comment: ""),
                            style: .Cancel, handler: { self.dismissController() })])
        }
    }
    
    func updateReceiveUI() {
        if BRAWWatchDataManager.sharedInstance.receiveMoneyQRCodeImage == nil {
            loadingIndicator.setHidden(false)
            qrCodeButton.setHidden(true)
        } else {
            loadingIndicator.setHidden(true)
            qrCodeButton.setHidden(false)
            var qrImg = BRAWWatchDataManager.sharedInstance.receiveMoneyQRCodeImage
            if customQR != nil {
                print("Using custom qr image")
                qrImg = customQR
            }
            qrCodeButton.setBackgroundImage(qrImg)
        }
    }
    
    @IBAction func qrCodeTap(sender: AnyObject?) {
        let ctx = BRAWKeypadModel(delegate: self)
        self.presentControllerWithName("Keypad", context: ctx)
    }
    
    // - MARK: Keypad delegate
    
    func keypadDidFinish(stringValueBits: String) {
        qrCodeButton.setHidden(true)
        loadingIndicator.setHidden(false)
        BRAWWatchDataManager.sharedInstance.requestQRCodeForBalance(stringValueBits) { (qrImage, error) -> Void in
            if let qrImage = qrImage {
                self.customQR = qrImage
            }
            self.updateReceiveUI()
            print("Got new qr image: \(qrImage) error: \(error)")
        }
        self.dismissController()
    }
    
    
}
