//
//  BRAWKeypad.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 12/27/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import Foundation
import WatchKit

protocol BRAWKeypadDelegate {
    func keypadDidFinish(stringValueBits: String)
}

class BRAWKeypadModel {
    var delegate: BRAWKeypadDelegate? = nil
    var valueInBits: String = "0"
    
    init(delegate d: BRAWKeypadDelegate?) {
        delegate = d
    }
}

class BRAWKeypad: WKInterfaceController {
    var digits: [String] = [String]()
    var ctx: BRAWKeypadModel?
    
    override func awakeWithContext(context: AnyObject?) {
        ctx = context as? BRAWKeypadModel
        digits = [String]()
        if let c = ctx {
            for s in c.valueInBits.componentsSeparatedByString("") {
                digits.append(s)
            }
        }
    }
    
    override func willDisappear() {
        ctx = nil
    }

    @IBOutlet var display: WKInterfaceLabel!
    
    @IBAction func one(sender: AnyObject?) { append("1") }
    
    @IBAction func two(sender: AnyObject?) { append("2") }
    
    @IBAction func three(sender: AnyObject?) { append("3") }
    
    @IBAction func four(sender: AnyObject?) { append("4") }
    
    @IBAction func five(sender: AnyObject?) { append("5") }
    
    @IBAction func six(sender: AnyObject?) { append("6") }
    
    @IBAction func seven(sender: AnyObject?) { append("7") }
    
    @IBAction func eight(sender: AnyObject?) { append("8") }
    
    @IBAction func nine(sender: AnyObject?) { append("9") }
    
    @IBAction func zero(sender: AnyObject?) { append("0") }
    
    @IBAction func del(sender: AnyObject?) {
        if digits.count > 0 {
            digits.removeLast()
            fmt()
        }
    }
    
    @IBAction func ok(sender: AnyObject?) {
        ctx?.delegate?.keypadDidFinish(ctx!.valueInBits)
    }
    
    func append(digit: String) {
        digits.append(digit)
        fmt()
    }
    
    func fmt() {
        var s = "ƀ"
        var d = digits
        while d.count > 0 && d[0] == "0" { d.removeFirst() } // remove remove forward zero padding
        while d.count < 3 { d.insert("0", atIndex: 0) } // add it back correctly
        for i in 0...(d.count - 1) {
            if i == d.count - 2 {
                s.appendContentsOf(".")
            }
            s.appendContentsOf(d[i])
        }
        display.setText(s)
        ctx?.valueInBits = s
            .stringByReplacingOccurrencesOfString(".", withString: "")
            .stringByReplacingOccurrencesOfString("ƀ", withString: "")
    }
}
