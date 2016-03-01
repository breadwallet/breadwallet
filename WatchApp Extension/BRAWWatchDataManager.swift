//
//  BRAWWatchDataManager.swift
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

enum WalletStatus {
    case Unknown
    case HasSetup
    case NotSetup
}

class BRAWWatchDataManager: NSObject, WCSessionDelegate {
    static let sharedInstance = BRAWWatchDataManager()
    static let ApplicationDataDidUpdateNotification = "ApplicationDataDidUpdateNotification"
    static let WalletStatusDidChangeNotification = "WalletStatusDidChangeNotification"
    static let WalletTxReceiveNotification = "WalletTxReceiveNotification"
    static let applicationContextDataFileName = "applicationContextData.txt"
    
    let session : WCSession =  WCSession.defaultSession()
    let timerFireInterval : NSTimeInterval = 7; // have iphone app sync with peer every 7 seconds
    
    var timer : NSTimer?
    
    private var appleWatchData : BRAppleWatchData?

    var balance : String? { return appleWatchData?.balance }
    var balanceInLocalCurrency : String? { return appleWatchData?.balanceInLocalCurrency }
    var receiveMoneyAddress : String? { return appleWatchData?.receiveMoneyAddress }
    var receiveMoneyQRCodeImage : UIImage? { return appleWatchData?.receiveMoneyQRCodeImage }
    var lastestTransction : String? { return appleWatchData?.lastestTransction }
    var transactionHistory : [BRAppleWatchTransactionData] {
        if let unwrappedAppleWatchData: BRAppleWatchData = appleWatchData,
            let transactions :[BRAppleWatchTransactionData] = unwrappedAppleWatchData.transactions{
            return  transactions
        } else {
            return [BRAppleWatchTransactionData]()
        }
    }
    var walletStatus : WalletStatus  {
        if appleWatchData == nil {
            return WalletStatus.Unknown
        } else if appleWatchData!.hasWallet {
            return WalletStatus.HasSetup
        } else {
            return WalletStatus.NotSetup
        }
    }
    
    lazy var dataFilePath: NSURL = {
            let filemgr = NSFileManager.defaultManager()
            let dirPaths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory,.UserDomainMask, true)
            let docsDir = dirPaths[0] as String
            return NSURL(fileURLWithPath: docsDir).URLByAppendingPathComponent(applicationContextDataFileName)
        }()
    
    override init() {
        super.init()
        if appleWatchData == nil {
            unarchiveData()
        }
        session.delegate = self
        session.activateSession()
    }
    
    func requestAllData() {
        if self.session.reachable {
            WKInterfaceDevice.currentDevice().playHaptic(WKHapticType.Click)
            let messageToSend = [
                AW_SESSION_REQUEST_TYPE: NSNumber(unsignedInt:AWSessionRquestTypeFetchData.rawValue),
                AW_SESSION_REQUEST_DATA_TYPE_KEY:
                        NSNumber(unsignedInt:AWSessionRquestDataTypeApplicationContextData.rawValue)
            ]
            session.sendMessage(messageToSend, replyHandler: { [unowned self] replyMessage in
                    if let data = replyMessage[AW_SESSION_RESPONSE_KEY] as? NSData {
                        if let unwrappedAppleWatchData
                                = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? BRAppleWatchData {
                            let previousAppleWatchData = self.appleWatchData
                            let previousWalletStatus = self.walletStatus
                            self.appleWatchData = unwrappedAppleWatchData
                            if previousAppleWatchData != self.appleWatchData {
                                self.archiveData(unwrappedAppleWatchData)
                                WKInterfaceDevice.currentDevice().playHaptic(WKHapticType.Click)
                                NSNotificationCenter.defaultCenter().postNotificationName(
                                    BRAWWatchDataManager.ApplicationDataDidUpdateNotification, object: nil)
                            }
                            if self.walletStatus != previousWalletStatus {
                                NSNotificationCenter.defaultCenter().postNotificationName(
                                    BRAWWatchDataManager.WalletStatusDidChangeNotification, object: nil)
                            }
                        }
                    }
                }, errorHandler: {error in
                    WKInterfaceDevice.currentDevice().playHaptic(WKHapticType.Failure)
                    print(error)
            })
        }
    }
    
    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        if let applicationContextData = applicationContext[AW_APPLICATION_CONTEXT_KEY] as? NSData {
            if let transferedAppleWatchData
                    = NSKeyedUnarchiver.unarchiveObjectWithData(applicationContextData) as? BRAppleWatchData {
                let previousWalletStatus = self.walletStatus
                appleWatchData = transferedAppleWatchData
                archiveData(transferedAppleWatchData)
                if self.walletStatus != previousWalletStatus {
                    NSNotificationCenter.defaultCenter().postNotificationName(
                        BRAWWatchDataManager.WalletStatusDidChangeNotification, object: nil)
                }
                NSNotificationCenter.defaultCenter().postNotificationName(
                    BRAWWatchDataManager.ApplicationDataDidUpdateNotification, object: nil)
                
            }
        }
    }
    
    func session(
        session: WCSession, didReceiveMessage message: [String : AnyObject],
        replyHandler: ([String : AnyObject]) -> Void) {
            print("Handle message from phone \(message)")
            if let noteV = message[AW_PHONE_NOTIFICATION_KEY],
                noteStr = noteV as? String,
                noteTypeV = message[AW_PHONE_NOTIFICATION_TYPE_KEY],
                noteTypeN = noteTypeV as? NSNumber
                where noteTypeN.unsignedIntValue == AWPhoneNotificationTypeTxReceive.rawValue {
                    let note = NSNotification(
                        name: BRAWWatchDataManager.WalletTxReceiveNotification, object: nil, userInfo: [
                            NSLocalizedDescriptionKey: noteStr]);
                    NSNotificationCenter.defaultCenter().postNotification(note)
            }
    }
    
    func requestQRCodeForBalance(bits: String, responseHandler: (qrImage: UIImage?, error: NSError?) -> Void) {
        if self.session.reachable {
            let msg = [
                AW_SESSION_REQUEST_TYPE: NSNumber(unsignedInt: AWSessionRquestTypeFetchData.rawValue),
                AW_SESSION_REQUEST_DATA_TYPE_KEY: NSNumber(unsignedInt: AWSessionRquestDataTypeQRCodeBits.rawValue),
                AW_SESSION_QR_CODE_BITS_KEY: bits
            ]
            session.sendMessage(msg,
                replyHandler: { (ctx) -> Void in
                    if let dat = ctx[AW_QR_CODE_BITS_KEY],
                        datDat = dat as? NSData,
                        img = UIImage(data: datDat) {
                            responseHandler(qrImage: img, error: nil)
                            return
                    }
                    responseHandler(qrImage: nil, error: NSError(domain: "", code: 500,
                        userInfo: [NSLocalizedDescriptionKey: "Unable to get new qr code"]))
                }, errorHandler: { (err) -> Void in
                    responseHandler(qrImage: nil, error: err)
            })
        }
    }
    
    func balanceAttributedString() -> NSAttributedString? {
       if let originalBalanceString = BRAWWatchDataManager.sharedInstance.balance {
            var balanceString = originalBalanceString.stringByReplacingOccurrencesOfString("ƀ", withString: "")
            balanceString = balanceString.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
            return attributedStringForBalance(balanceString)
        }
        return nil
    }
    
    private func attributedStringForBalance(balance: String?)-> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        
        attributedString.appendAttributedString(
            NSAttributedString(string: "ƀ", attributes: [NSForegroundColorAttributeName : UIColor.grayColor()]))
        
        attributedString.appendAttributedString(
            NSAttributedString(string: balance ?? "0", attributes:
                [NSForegroundColorAttributeName : UIColor.whiteColor()]))
        
        return attributedString
    }
    
    func archiveData(appleWatchData: BRAppleWatchData){
        NSKeyedArchiver.archivedDataWithRootObject(appleWatchData).writeToURL(dataFilePath, atomically: true)
    }
    
    func unarchiveData() {
        if let data = NSData(contentsOfURL: dataFilePath) {
            appleWatchData = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? BRAppleWatchData
        }
    }
    
    func setupTimer() {
        destoryTimer()
        let weakTimerTarget = BRAWWeakTimerTarget(initTarget: self, initSelector: "requestAllData")
        timer = NSTimer.scheduledTimerWithTimeInterval(
            timerFireInterval, target: weakTimerTarget, selector: "timerDidFire", userInfo: nil, repeats: true)
    }
    
    func destoryTimer() {
        if let currentTimer : NSTimer = timer {
            currentTimer.invalidate();
            timer = nil
        }
    }
}
