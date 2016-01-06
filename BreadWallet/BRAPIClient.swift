//
//  BRAPIClient.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 11/4/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
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


import Foundation

let BRAPIClientErrorDomain = "BRApiClientErrorDomain"

public typealias URLSessionTaskHandler = (NSData?, NSHTTPURLResponse?, NSError?) -> Void
public typealias URLSessionChallengeHandler = (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void

extension String {
    static var urlQuoteCharacterSet: NSCharacterSet {
        let cset = NSMutableCharacterSet.URLQueryAllowedCharacterSet().mutableCopy() as! NSMutableCharacterSet
        cset.removeCharactersInString("?=&")
        return cset
    }
    
    var urlEscapedString: String {
        return self.stringByAddingPercentEncodingWithAllowedCharacters(
            String.urlQuoteCharacterSet)!
    }
}

func getHeaderValue(k: String, d: Dictionary<NSObject, AnyObject>) -> String? {
    if let v = d[k] as? String { // short path: attempt to get the header directly
        return v
    }
    let lkKey = k.lowercaseString // long path: compare lowercase keys
    for (lk, lv) in d {
        if lk is String {
            let lks = lk as! String
            if lks.lowercaseString == lkKey {
                if let lvs = lv as? String {
                    return lvs
                }
            }
        }
    }
    return nil
}

func getAuthKey() -> BRKey? {
    if let manager = BRWalletManager.sharedInstance(), authKey = manager.authPrivateKey {
        return BRKey(privateKey: authKey)
    }
    return nil
}

func getDeviceId() -> String {
    let ud = NSUserDefaults.standardUserDefaults()
    if let s = ud.stringForKey("BR_DEVICE_ID") {
        return s
    }
    let s = CFUUIDCreateString(nil, CFUUIDCreate(nil)) as String
    ud.setValue(s, forKey: "BR_DEVICE_ID")
    print("new device id \(s)")
    return s
}

func isBreadChallenge(r: NSHTTPURLResponse) -> Bool {
    if let challenge = getHeaderValue("www-authenticate", d: r.allHeaderFields) {
        if challenge.lowercaseString.hasPrefix("bread") {
            return true
        }
    }
    return false
}

func buildURLResourceString(url: NSURL?) -> String {
    var urlStr = ""
    if let url = url, path = url.path {
        urlStr = "\(path)"
        if let query = url.query {
            if query.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0 {
                urlStr = "\(url)?\(query)"
            }
        }
    }
    return urlStr
}

func buildRequestSigningString(r: NSMutableURLRequest) -> String {
    let headers = r.allHTTPHeaderFields ?? Dictionary<String, String>()
    var parts = [
        r.HTTPMethod,
        "",
        getHeaderValue("content-type", d: headers) ?? "",
        getHeaderValue("date", d: headers) ?? "",
        buildURLResourceString(r.URL)
    ]
    switch r.HTTPMethod {
    case "POST", "PUT", "PATCH":
        if let d = r.HTTPBody {
            let sha = d.SHA256()
            parts[1] = NSData(UInt256: sha).base58String()
        }
    default: break
    }
    return parts.joinWithSeparator("\n")
}

func buildResponseSigningString(req: NSMutableURLRequest, res: NSHTTPURLResponse, data: NSData? = nil) -> String {
    let parts: [String] = [
        req.HTTPMethod,
        "\(res.statusCode)",
        data != nil ? NSData(UInt256: data!.SHA256()).base58String() : "",
        getHeaderValue("content-type", d: res.allHeaderFields) ?? "",
        getHeaderValue("date", d: res.allHeaderFields) ?? "",
        buildURLResourceString(res.URL)
    ]
    
    return parts.joinWithSeparator("\n")
}

var rfc1123DateFormatter: NSDateFormatter {
    let fmt = NSDateFormatter()
    fmt.timeZone = NSTimeZone(abbreviation: "GMT")
    fmt.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'";
    fmt.locale = NSLocale(localeIdentifier: "en_US")
    return fmt
}

func httpDateNow() -> String {
    return rfc1123DateFormatter.stringFromDate(NSDate())
}

@objc public class BRAPIClient: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate {
    var logEnabled = true
    var proto = "https"
    var host = "api.breadwallet.com"
    
    var session: NSURLSession {
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        return NSURLSession(configuration: config, delegate: self, delegateQueue: queue)
    }
    var queue: NSOperationQueue {
        return NSOperationQueue()
    }
    
    var baseUrl: String {
        return "\(proto)://\(host)"
    }
    
    var userAccountKey: String {
        return baseUrl
    }
    
    var serverPubKey: BRKey {
        let encoded = "24jsCR3itNGbbmYbZnG6jW8gjguhqybCXsoUAgfqdjprz"
        return BRKey(publicKey: NSData(base58String: encoded))!
    }
    
    // the singleton
    static let sharedClient = BRAPIClient()
    
    
    func log(format: String, args: CVarArgType...) -> Int? {
        if !logEnabled {
            return 1
        }
        let s = String(format: format, arguments: args)
        print("[BRAPIClient] \(s)")
        return 2
    }
    
    // MARK: Networking functions
    
    // Constructs a full NSURL for a given path and url parameters
    func url(path: String, args: Dictionary<String, String>? =  nil) -> NSURL {
        func joinPath(k: String...) -> NSURL {
            return NSURL(string: ([baseUrl] + k).joinWithSeparator(""))!
        }
        
        if let args = args {
            return joinPath(path + "?" + args.map({ (elem) -> String in
                return "\(elem.0.urlEscapedString)=\(elem.1.urlEscapedString)"
            }).joinWithSeparator("&"))
        } else {
            return joinPath(path)
        }
    }
    
    func signRequest(request: NSURLRequest) -> NSURLRequest {
        let mutableRequest = request.mutableCopy() as! NSMutableURLRequest
        let dateHeader = getHeaderValue("date", d: mutableRequest.allHTTPHeaderFields ?? Dictionary<String, String>())
        if dateHeader == nil {
            // add Date header if necessary
            mutableRequest.setValue(httpDateNow(), forHTTPHeaderField: "Date")
        }
        do {
            if let tokenData = try BRKeychain.loadDataForUserAccount(userAccountKey),
                token = tokenData["token"], authKey = getAuthKey() {
                let sha = buildRequestSigningString(mutableRequest).dataUsingEncoding(NSUTF8StringEncoding)!.SHA256_2()
                let sig = authKey.compactSign(sha)!.base58String()
                mutableRequest.setValue("bread \(token):\(sig)", forHTTPHeaderField: "Authorization")
            }
        } catch let e as BRKeychainError {
            log("keychain error fetching tokoen \(e)")
        } catch let e {
            log("unexpected error fetching keychain data \(e)")
        }
        return mutableRequest.copy() as! NSURLRequest
    }
    
    func verifyResponse(request: NSMutableURLRequest, response: NSHTTPURLResponse, data: NSData?) -> Bool {
        // ensure the signature header is present and in the correct format
        guard let sigHeader = getHeaderValue("signature", d: response.allHeaderFields),
            sigRange = sigHeader.rangeOfString("bread ")
            where sigHeader.startIndex.distanceTo(sigRange.startIndex) == 0 else { return false }
        
        // extract signing signature bytes and signing string
        let sigStr = sigHeader[sigRange.endIndex..<sigHeader.endIndex],
            sig = NSData(base58String: sigStr),
            signingString = buildResponseSigningString(request, res: response, data: data)
        
        // extract the public key and ensure it equals the one we have configured
        if let sha = signingString.dataUsingEncoding(NSUTF8StringEncoding)?.SHA256_2(),
            pk = BRKey(recoveredFromCompactSig: sig, andMessageDigest: sha),
            pkDatA = pk.publicKey, pkDatB = serverPubKey.publicKey
            where pkDatA.isEqualToData(pkDatB) { return true }
        return false
    }
    
    func dataTaskWithRequest(request: NSURLRequest, authenticated: Bool = false, verify: Bool = true,
                             retryCount: Int = 0, handler: URLSessionTaskHandler) -> NSURLSessionDataTask {
        let start = NSDate()
        var logLine = ""
        if let meth = request.HTTPMethod, u = request.URL {
            logLine = "\(meth) \(u) auth=\(authenticated) retry=\(retryCount)"
        }
        let origRequest = request.mutableCopy() as! NSURLRequest
        var actualRequest = request
        if authenticated && getAuthKey() != nil {
            actualRequest = signRequest(request)
        }
        return session.dataTaskWithRequest(actualRequest) { (data, resp, err) -> Void in
            let end = NSDate()
            let dur = Int(end.timeIntervalSinceDate(start) * 1000)
            if let httpResp = resp as? NSHTTPURLResponse {
                var errStr = ""
                if httpResp.statusCode >= 400 {
                    if let data = data, s = NSString(data: data, encoding: NSUTF8StringEncoding) {
                        errStr = s as String
                    }
                }
                var verified = true
                if verify {
                    let mreq = actualRequest.mutableCopy() as! NSMutableURLRequest
                    verified = self.verifyResponse(mreq, response: httpResp, data: data)
                }
                
                self.log("\(logLine) -> status=\(httpResp.statusCode) duration=\(dur)ms " +
                         "verified=\(verified) errStr=\(errStr)")
                
                if !verified {
                    return handler(nil, nil, NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString("Unable to verify server identity", comment: "")]))
                }
                if authenticated && isBreadChallenge(httpResp) {
                    self.log("got authentication challenge from API - will attempt to get token")
                    self.getToken({ (err) -> Void in
                        if err != nil && retryCount < 1 { // retry once
                            self.log("error retrieving token: \(err) - will retry")
                            dispatch_after(1, dispatch_get_main_queue(), { () -> Void in
                                self.dataTaskWithRequest(
                                    origRequest, authenticated: authenticated,
                                    retryCount: retryCount + 1, handler: handler).resume()
                            })
                        } else if err != nil && retryCount > 0 { // fail if we already retried
                            self.log("error retrieving token: \(err) - will no longer retry")
                            handler(nil, nil, err)
                        } else if retryCount < 1 { // no error, so attempt the request again
                            self.log("retrieved token, so retrying the original request")
                            self.dataTaskWithRequest(
                                origRequest, authenticated: authenticated,
                                retryCount: retryCount + 1, handler: handler).resume()
                        } else {
                            self.log("retried token multiple times, will not retry again")
                            handler(data, httpResp, err)
                        }
                    })
                } else {
                    handler(data, httpResp, err)
                }
            } else {
                self.log("\(logLine) encountered connection error \(err)")
                handler(data, nil, err)
            }
        }
    }
    
    // retrieve a token and save it in the keychain data for this account
    func getToken(handler: (NSError?) -> Void) -> Void {
        if getAuthKey() == nil {
            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Wallet not ready", comment: "")]))
        }
        let req = NSMutableURLRequest(URL: url("/token"))
        req.HTTPMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let reqJson = [
            "pubKey": getAuthKey()!.publicKey!.base58String(),
            "deviceID": getDeviceId()
        ]
        do {
            let dat = try NSJSONSerialization.dataWithJSONObject(reqJson, options: .PrettyPrinted)
            req.HTTPBody = dat
        } catch (let e) {
            log("JSON Serialization error \(e)")
            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("JSON Serialization Error", comment: "")]))
        }
        let task = session.dataTaskWithRequest(req) { (data, resp, err) -> Void in
            if let httpResp = resp as? NSHTTPURLResponse {
                // unsuccessful response from the server
                if httpResp.statusCode != 200 {
                    if let data = data {
                        if let s = String(data: data, encoding: NSUTF8StringEncoding) {
                            self.log("Token error: \(s)")
                        }
                    }
                    return handler(NSError(domain: BRAPIClientErrorDomain, code: httpResp.statusCode, userInfo: [
                            NSLocalizedDescriptionKey: NSLocalizedString("Unable to retrieve API token", comment: "")]))
                }
            }
            if let data = data {
                do {
                    let json = try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments)
                    self.log("POST /token: \(json)")
                    if let topObj = json as? NSDictionary,
                        tok = topObj["token"] as? NSString,
                        uid = topObj["userID"] as? NSString {
                        // success! store it in the keychain
                        let kcData = ["token": tok, "userID": uid]
                        do {
                            try BRKeychain.saveData(kcData, forUserAccount: self.userAccountKey)
                        } catch let e {
                            self.log("Error saving token in keychain \(e)")
                            return handler(NSError(domain: BRAPIClientErrorDomain, code: 500, userInfo: [
                                NSLocalizedDescriptionKey: NSLocalizedString("Unable to save API token", comment: "")]))
                        }
                    }
                } catch let e {
                    self.log("JSON Deserialization error \(e)")
                }
            }
            handler(err)
        }
        task.resume()
    }
    
    // MARK: URLSession Delegate
    
    public func URLSession(session: NSURLSession, didBecomeInvalidWithError error: NSError?) {
        log("URLSession didBecomeInvalidWithError: \(error)")
    }
    
    public func URLSession(session: NSURLSession, task: NSURLSessionTask,
                           didReceiveChallenge: NSURLAuthenticationChallenge,
                           completionHandler: URLSessionChallengeHandler) {
            log("URLSession task \(task) didReceivechallenge \(didReceiveChallenge.protectionSpace)")
            
    }
    
    public func URLSession(session: NSURLSession, didReceiveChallenge: NSURLAuthenticationChallenge,
                           completionHandler: URLSessionChallengeHandler) {
        log("URLSession didReceiveChallenge \(didReceiveChallenge) \(didReceiveChallenge.protectionSpace)")
        // handle HTTPS authentication
        if didReceiveChallenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if (didReceiveChallenge.protectionSpace.host == host
                && didReceiveChallenge.protectionSpace.serverTrust != nil) {
                log("URLSession challenge accepted!")
                completionHandler(.UseCredential,
                    NSURLCredential(forTrust: didReceiveChallenge.protectionSpace.serverTrust!))
            } else {
                log("URLSession challenge rejected")
                completionHandler(.RejectProtectionSpace, nil)
            }
        }
    }
    
    // MARK: API Functions
    
    // Fetches the /v1/fee-per-kb endpoint
    public func feePerKb(handler: (feePerKb: uint_fast64_t, error: String?) -> Void) {
        let req = NSURLRequest(URL: url("/v1/fee-per-kb"))
        let task = self.dataTaskWithRequest(req) { (data, response, err) -> Void in
            var feePerKb: uint_fast64_t = 0
            var errStr: String? = nil
            if err == nil {
                do {
                    let parsedObject: AnyObject? = try NSJSONSerialization.JSONObjectWithData(
                        data!, options: NSJSONReadingOptions.AllowFragments)
                    if let top = parsedObject as? NSDictionary, n = top["fee_per_kb"] as? NSNumber {
                        feePerKb = n.unsignedLongLongValue
                    }
                } catch (let e) {
                    self.log("fee-per-kb: error parsing json \(e)")
                }
                if feePerKb == 0 {
                    errStr = "invalid json"
                }
            } else {
                self.log("fee-per-kb network error: \(err)")
                errStr = "bad network connection"
            }
            handler(feePerKb: feePerKb, error: errStr)
        }
        task.resume()
    }
    
    public func me() {
        let req = NSURLRequest(URL: url("/me"))
        let task = dataTaskWithRequest(req, authenticated: true) { (data, resp, err) -> Void in
            if let data = data {
                if let s = String(data: data, encoding: NSUTF8StringEncoding) {
                    self.log("GET /me: \(s)")
                }
            }
        }
        task.resume()
    }
    
    // MARK: Assets API
    
    public class func bundleURL(bundleName: String) -> NSURL {
        let fm = NSFileManager.defaultManager()
        let docsUrl = fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
        let bundleDirUrl = docsUrl.URLByAppendingPathComponent("bundles", isDirectory: true)
        let bundleUrl = bundleDirUrl.URLByAppendingPathComponent("\(bundleName)-extracted", isDirectory: true)
        return bundleUrl
    }
    
    public func updateBundle(bundleName: String, handler: (error: String?) -> Void) {
        // 1. check if we already have a bundle given the name
        // 2. if we already have it:
        //    2a. get the sha256 of the on-disk bundle
        //    2b. request the versions of the bundle from server
        //    2c. request the diff between what we have and the newest one, if ours is not already the newest
        //    2d. apply the diff and extract to the bundle folder
        // 3. otherwise:
        //    3a. download and extract the bundle
        
        // set up the environment
        let fm = NSFileManager.defaultManager()
        let docsUrl = fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
        let bundleDirUrl = docsUrl.URLByAppendingPathComponent("bundles", isDirectory: true)
        let bundleUrl = bundleDirUrl.URLByAppendingPathComponent("\(bundleName).tar")
        let bundleDirPath = bundleDirUrl.path!
        let bundlePath = bundleUrl.path!
        let bundleExtractedUrl = bundleDirUrl.URLByAppendingPathComponent("\(bundleName)-extracted")
        let bundleExtractedPath = bundleExtractedUrl.path!
        
        // determines if the bundle exists, but also creates the bundles/extracted directory if it doesn't exist
        func exists() throws -> Bool {
            var attrs = try? fm.attributesOfItemAtPath(bundleDirPath)
            if attrs == nil {
                try fm.createDirectoryAtPath(bundleDirPath, withIntermediateDirectories: true, attributes: nil)
                attrs = try fm.attributesOfItemAtPath(bundleDirPath)
            }
            var attrsExt = try? fm.attributesOfFileSystemForPath(bundleExtractedPath)
            if attrsExt == nil {
                try fm.createDirectoryAtPath(bundleExtractedPath, withIntermediateDirectories: true, attributes: nil)
                attrsExt = try fm.attributesOfItemAtPath(bundleExtractedPath)
            }
            return fm.fileExistsAtPath(bundlePath)
        }
        
        // extracts the bundle
        func extract() throws {
            try BRTar.createFilesAndDirectoriesAtPath(bundleExtractedPath, withTarPath: bundlePath)
        }
        
        guard let bundleExists = try? exists() else {
            return handler(error: NSLocalizedString("error determining if bundle exists", comment: "")) }
        
        if bundleExists {
            // bundle exists, download and apply the diff, then remove diff file
            log("bundle \(bundleName) exists, fetching diff for most recent version")
            
            guard let curBundleContents = NSData(contentsOfFile: bundlePath) else {
                return handler(error: NSLocalizedString("error reading current bundle", comment: "")) }
            
            let curBundleSha = NSData(UInt256: curBundleContents.SHA256())!.hexString
            
            dataTaskWithRequest(NSURLRequest(URL: url("/assets/bundles/\(bundleName)/versions")))
                { (data, resp, err) -> Void in
                    if let data = data,
                        parsed = try? NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments),
                        top = parsed as? NSDictionary,
                        versions = top["versions"] as? [String]
                        where err == nil {
                            if versions.indexOf(curBundleSha) == (versions.count - 1) { // have the most recent version
                                self.log("already at most recent version of bundle \(bundleName)")
                                do {
                                    try extract()
                                    return handler(error: nil)
                                } catch let e {
                                    return handler(error:
                                        NSLocalizedString("error extracting bundle: " + "\(e)", comment: ""))
                                }
                            } else { // don't have the most recent version, download diff
                                self.log("Fetching most recent version of bundle \(bundleName)")
                                let req = NSURLRequest(URL:
                                    self.url("/assets/bundles/\(bundleName)/diff/\(curBundleSha)"))
                                self.dataTaskWithRequest(req, handler: { (diffDat, diffResp, diffErr) -> Void in
                                    if let diffDat = diffDat,
                                        diffPath = bundleDirUrl.URLByAppendingPathComponent("\(bundleName).diff").path,
                                        oldBundlePath = bundleDirUrl.URLByAppendingPathComponent("\(bundleName).old").path
                                    where diffErr == nil {
                                        do {
                                            if fm.fileExistsAtPath(diffPath) {
                                                try fm.removeItemAtPath(diffPath)
                                            }
                                            if fm.fileExistsAtPath(oldBundlePath) {
                                                try fm.removeItemAtPath(oldBundlePath)
                                            }
                                            try diffDat.writeToFile(diffPath, options: .DataWritingAtomic)
                                            try fm.moveItemAtPath(bundlePath, toPath: oldBundlePath)
                                            try BRBSPatch.patch(
                                                oldBundlePath, newFilePath: bundlePath, patchFilePath: diffPath)
                                            try fm.removeItemAtPath(diffPath)
                                            try fm.removeItemAtPath(oldBundlePath)
                                            try extract()
                                            return handler(error: nil)
                                        } catch let e {
                                            // something failed, clean up whatever we can, next attempt will download fresh
                                            _ = try? fm.removeItemAtPath(diffPath)
                                            _ = try? fm.removeItemAtPath(oldBundlePath)
                                            _ = try? fm.removeItemAtPath(bundlePath)
                                            return handler(error:
                                                NSLocalizedString("error downloading diff: " + "\(e)", comment: ""))
                                        }
                                    }
                                }).resume()
                            }
                        }
                    else {
                        return handler(error: NSLocalizedString("error determining versions", comment: ""))
                    }
                }.resume()
        } else {
            // bundle doesn't exist. download a fresh copy
            log("bundle \(bundleName) doesn't exist, downloading new copy")
            let req = NSURLRequest(URL: url("/assets/bundles/\(bundleName)/download"))
            dataTaskWithRequest(req) { (data, response, err) -> Void in
                if err != nil {
                    return handler(error: NSLocalizedString("error fetching bundle: ", comment: "") + "\(err)")
                }
                if let data = data {
                    do {
                        try data.writeToFile(bundlePath, options: .DataWritingAtomic)
                        try extract()
                        return handler(error: nil)
                    } catch let e {
                        return handler(error: NSLocalizedString("error writing bundle file: ", comment: "") + "\(e)")
                    }
                }
            }.resume()
        }
    }
    
    public func serveBundle(bundleName: String, debugURL: String? = nil) -> BRHTTPServer? {
        let ret = BRHTTPServer(baseDirectory: BRAPIClient.bundleURL(bundleName))
        do {
            try ret.start()
            if debugURL != nil {
                ret.debugFrom(NSURL(string: debugURL!))
            }
            return ret
        } catch let e {
            log("Error starting http server: \(e)")
        }
        return nil
    }
}

extension NSData {
    var hexString : String {
        let buf = UnsafePointer<UInt8>(bytes)
        let charA = UInt8(UnicodeScalar("a").value)
        let char0 = UInt8(UnicodeScalar("0").value)
        
        func itoh(i: UInt8) -> UInt8 {
            return (i > 9) ? (charA + i - 10) : (char0 + i)
        }
        
        let p = UnsafeMutablePointer<UInt8>.alloc(length * 2)
        
        for i in 0..<length {
            p[i*2] = itoh((buf[i] >> 4) & 0xF)
            p[i*2+1] = itoh(buf[i] & 0xF)
        }
        
        return NSString(bytesNoCopy: p, length: length*2, encoding: NSUTF8StringEncoding, freeWhenDone: true) as! String
    }
}

let BreadDefaultService = "org.voisine.breadwallet"

enum BRKeychainError: String, ErrorType {
    // this is borrowed from the "Locksmith" library: https://github.com/matthewpalmer/Locksmith
    case Allocate = "Failed to allocate memory."
    case AuthFailed = "Authorization/Authentication failed."
    case Decode = "Unable to decode the provided data."
    case Duplicate = "The item already exists."
    case InteractionNotAllowed = "Interaction with the Security Server is not allowed."
    case NoError = "No error."
    case NotAvailable = "No trust results are available."
    case NotFound = "The item cannot be found."
    case Param = "One or more parameters passed to the function were not valid."
    case RequestNotSet = "The request was not set"
    case TypeNotFound = "The type was not found"
    case UnableToClear = "Unable to clear the keychain"
    case Undefined = "An undefined error occurred"
    case Unimplemented = "Function or operation not implemented."
    
    init?(fromStatusCode code: Int) {
        switch code {
        case Int(errSecAllocate):
            self = Allocate
        case Int(errSecAuthFailed):
            self = AuthFailed
        case Int(errSecDecode):
            self = Decode
        case Int(errSecDuplicateItem):
            self = Duplicate
        case Int(errSecInteractionNotAllowed):
            self = InteractionNotAllowed
        case Int(errSecItemNotFound):
            self = NotFound
        case Int(errSecNotAvailable):
            self = NotAvailable
        case Int(errSecParam):
            self = Param
        case Int(errSecUnimplemented):
            self = Unimplemented
        default:
            return nil
        }
    }
}

class BRKeychain {
    // this API is inspired by the aforementioned Locksmith library
    static func loadDataForUserAccount(account: String,
                                       inService service: String = BreadDefaultService) throws -> [String: AnyObject]? {
        var q = getBaseQuery(account, service: service)
        q[String(kSecReturnData)] = kCFBooleanTrue
        q[String(kSecMatchLimit)] = kSecMatchLimitOne
        var res: AnyObject?
        let status: OSStatus = withUnsafeMutablePointer(&res) {
            SecItemCopyMatching(q, UnsafeMutablePointer($0))
        }
        if let err = BRKeychainError(fromStatusCode: Int(status)) {
            switch err {
            case .NotFound, .NotAvailable:
                return nil
            default:
                throw err
            }
        }
        if let res = res as? NSData {
            return NSKeyedUnarchiver.unarchiveObjectWithData(res) as? [String: AnyObject]
        }
        print("Unable to unarchive keychain data... deleting data")
        do {
            try deleteDataForUserAccount(account, inService: service)
        } catch let e as BRKeychainError {
            print("Unable to delete from keychain: \(e)")
        }
        return nil
    }
    
    static func saveData(data: [String: AnyObject], forUserAccount account: String,
                         inService service: String = BreadDefaultService) throws {
        do {
            try deleteDataForUserAccount(account, inService: service)
        } catch let e as BRKeychainError {
            print("Unable to delete from keychain: \(e)")
        }
        var q = getBaseQuery(account, service: service)
        q[String(kSecValueData)] = NSKeyedArchiver.archivedDataWithRootObject(data)
        let status: OSStatus = SecItemAdd(q, nil)
        if let err = BRKeychainError(fromStatusCode: Int(status)) {
            throw err
        }
    }
    
    static func deleteDataForUserAccount(account: String, inService service: String = BreadDefaultService) throws {
        let q = getBaseQuery(account, service: service)
        let status: OSStatus = SecItemDelete(q)
        if let err = BRKeychainError(fromStatusCode: Int(status)) {
            throw err
        }
    }
    
    private static func getBaseQuery(account: String, service: String) -> [String: AnyObject] {
        let query = [
            String(kSecClass): String(kSecClassGenericPassword),
            String(kSecAttrAccount): account,
            String(kSecAttrService): service,
            String(kSecAttrAccessible): String(kSecAttrAccessibleAlwaysThisDeviceOnly)
        ]
        return query
    }
}

enum BRTarError: ErrorType {
    case Unknown
    case FileDoesntExist
}

enum BRTarType {
    case File
    case Directory
    case NullBlock
    case HeaderBlock
    case Unsupported
    case Invalid
    
    init(fromData: NSData) {
        let byte = UnsafePointer<CChar>(fromData.bytes)[0]
        switch byte {
        case CChar(48): // "0"
            self = File
        case CChar(53): // "5"
            self = Directory
        case CChar(0):
            self = NullBlock
        case CChar(120): // "x"
            self = HeaderBlock
        case CChar(49), CChar(50), CChar(51), CChar(52), CChar(53), CChar(54), CChar(55), CChar(103):
            // "1, 2, 3, 4, 5, 6, 7, g"
            self = Unsupported
        default:
            BRTar.log("invalid block type: \(byte)")
            self = Invalid
        }
    }
}

class BRTar {
    static let tarBlockSize: UInt64 = 512
    static let tarTypePosition: UInt64 = 156
    static let tarNamePosition: UInt64 = 0
    static let tarNameSize: UInt64 = 100
    static let tarSizePosition: UInt64 = 124
    static let tarSizeSize: UInt64 = 12
    static let tarMaxBlockLoadInMemory: UInt64 = 100
    static let tarLogEnabled: Bool = false
    
    static func createFilesAndDirectoriesAtPath(path: String, withTarPath tarPath: String) throws {
        let fm = NSFileManager.defaultManager()
        if !fm.fileExistsAtPath(tarPath) {
            log("tar file \(tarPath) does not exist")
            throw BRTarError.FileDoesntExist
        }
        let attrs = try fm.attributesOfItemAtPath(tarPath)
        guard let tarFh = NSFileHandle(forReadingAtPath: tarPath) else {
            log("could not open tar file for reading")
            throw BRTarError.Unknown
        }
        var loc: UInt64 = 0
        guard let size = attrs[NSFileSize]?.unsignedLongLongValue else {
            log("could not read tar file size")
            throw BRTarError.Unknown
        }
        
        while loc < size {
            var blockCount: UInt64 = 1
            let tarType = readTypeAtLocation(loc, fromHandle: tarFh)
            switch tarType {
            case .File:
                // read name
                let name = try readNameAtLocation(loc, fromHandle: tarFh)
                log("got file name from tar \(name)")
                let newFilePath = (path as NSString).stringByAppendingPathComponent(name)
                log("will write to \(newFilePath)")
                var size = readSizeAtLocation(loc, fromHandle: tarFh)
                log("its size is \(size)")
                
                if fm.fileExistsAtPath(newFilePath) {
                    try fm.removeItemAtPath(newFilePath)
                }
                if size == 0 {
                    // empty file
                    try "" .writeToFile(newFilePath, atomically: true, encoding: NSUTF8StringEncoding)
                    break
                }
                blockCount += (size - 1) / tarBlockSize + 1
                // write file
                fm.createFileAtPath(newFilePath, contents: nil, attributes: nil)
                guard let destFh = NSFileHandle(forWritingAtPath: newFilePath) else {
                    log("unable to open destination file for writing")
                    throw BRTarError.Unknown
                }
                tarFh.seekToFileOffset(loc + tarBlockSize)
                let maxSize = tarMaxBlockLoadInMemory * tarBlockSize
                while size > maxSize {
                    autoreleasepool({ () -> () in
                        destFh.writeData(tarFh.readDataOfLength(Int(maxSize)))
                        size -= maxSize
                    })
                }
                destFh.writeData(tarFh.readDataOfLength(Int(size)))
                destFh.closeFile()
                log("success writing file")
                break
            case .Directory:
                let name = try readNameAtLocation(loc, fromHandle: tarFh)
                log("got new directory name \(name)")
                let dirPath = (path as NSString).stringByAppendingPathComponent(name)
                log("will create directory at \(dirPath)")
                
                if fm.fileExistsAtPath(dirPath) {
                    try fm.removeItemAtPath(dirPath) // will automatically recursively remove directories if exists
                }
                
                try fm.createDirectoryAtPath(dirPath, withIntermediateDirectories: true, attributes: nil)
                log("success creating directory")
                break
            case .NullBlock:
                break
            case .HeaderBlock:
                blockCount++
                break
            case .Unsupported:
                let size = readSizeAtLocation(loc, fromHandle: tarFh)
                blockCount += size / tarBlockSize
                break
            case .Invalid:
                log("Invalid block encountered")
                throw BRTarError.Unknown
            }
            loc += blockCount * tarBlockSize
            log("new location \(loc)")
        }
    }
    
    static private func readTypeAtLocation(location: UInt64, fromHandle handle: NSFileHandle) -> BRTarType {
        log("reading type at location \(location)")
        handle.seekToFileOffset(location + tarTypePosition)
        let typeDat = handle.readDataOfLength(1)
        let ret = BRTarType(fromData: typeDat)
        log("type: \(ret)")
        return ret
    }
    
    static private func readNameAtLocation(location: UInt64, fromHandle handle: NSFileHandle) throws -> String {
        handle.seekToFileOffset(location + tarNamePosition)
        guard let ret = NSString(data: handle.readDataOfLength(Int(tarNameSize)), encoding: NSASCIIStringEncoding)
            else {
                log("unable to read name")
                throw BRTarError.Unknown
            }
        return ret as String
    }
    
    static private func readSizeAtLocation(location: UInt64, fromHandle handle: NSFileHandle) -> UInt64 {
        handle.seekToFileOffset(location + tarSizePosition)
        let sizeDat = handle.readDataOfLength(Int(tarSizeSize))
        let octal = NSString(data: sizeDat, encoding: NSASCIIStringEncoding)!
        log("size octal: \(octal)")
        let dec = strtoll(octal.UTF8String, nil, 8)
        log("size decimal: \(dec)")
        return UInt64(dec)
    }
    
    static private func log(string: String) {
        if tarLogEnabled {
            print("[BRTar] \(string)")
        }
    }
}

enum BRBSPatchError: ErrorType {
    case Unknown
    case CorruptPatch
    case PatchFileDoesntExist
    case OldFileDoesntExist
}


class BRBSPatch {
    static let patchLogEnabled = true
    
    static func patch(oldFilePath: String, newFilePath: String, patchFilePath: String) throws -> UnsafeMutablePointer<CUnsignedChar> {
        func offtin(b: UnsafePointer<CUnsignedChar>) -> off_t {
            var y = off_t(b[0])
            y |= off_t(b[1]) << 8
            y |= off_t(b[2]) << 16
            y |= off_t(b[3]) << 24
            y |= off_t(b[4]) << 32
            y |= off_t(b[5]) << 40
            y |= off_t(b[6]) << 48
            y |= off_t(b[7] & 0x7f) << 56
            if Int(b[7]) & 0x80 != 0 {
                y = -y
            }
            return y
        }
        let patchFilePathBytes = UnsafePointer<Int8>((patchFilePath as NSString).UTF8String)
        let r = UnsafePointer<Int8>(("r" as NSString).UTF8String)
        
        // open patch file
        guard let f = NSFileHandle(forReadingAtPath: patchFilePath) else {
            log("unable to open file for reading at path \(patchFilePath)")
            throw BRBSPatchError.PatchFileDoesntExist
        }
        
        // read header
        let headerData = f.readDataOfLength(32)
        let header = UnsafePointer<CUnsignedChar>(headerData.bytes)
        if headerData.length != 32 {
            log("incorrect header read length \(headerData.length)")
            throw BRBSPatchError.CorruptPatch
        }
        
        // check for appropriate magic
        let magicData = headerData.subdataWithRange(NSMakeRange(0, 8))
        if let magic = NSString(data: magicData, encoding: NSASCIIStringEncoding)
            where magic != "BSDIFF40" {
                log("incorrect magic: \(magic)")
                throw BRBSPatchError.CorruptPatch
            }
        
        // read lengths from header
        let bzCrtlLen = offtin(header + 8)
        let bzDataLen = offtin(header + 16)
        let newSize = offtin(header + 24)
        
        if bzCrtlLen < 0 || bzDataLen < 0 || newSize < 0 {
            log("incorrect header data: crtlLen: \(bzCrtlLen) dataLen: \(bzDataLen) newSize: \(newSize)")
            throw BRBSPatchError.CorruptPatch
        }
        
        // close patch file and re-open it with bzip2 at the right positions
        f.closeFile()
        
        let cpf = fopen(patchFilePathBytes, r)
        if cpf == nil {
            let s = String.fromCString(strerror(errno))
            let ff = String.fromCString(patchFilePathBytes)
            log("unable to open patch file c: \(s) \(ff)")
            throw BRBSPatchError.Unknown
        }
        let cpfseek = fseeko(cpf, 32, SEEK_SET)
        if cpfseek != 0 {
            log("unable to seek patch file c: \(cpfseek)")
            throw BRBSPatchError.Unknown
        }
        let cbz2err = UnsafeMutablePointer<Int32>.alloc(1)
        let cpfbz2 = BZ2_bzReadOpen(cbz2err, cpf, 0, 0, nil, 0)
        if cpfbz2 == nil {
            log("unable to bzopen patch file c: \(cbz2err)")
            throw BRBSPatchError.Unknown
        }
        let dpf = fopen(patchFilePathBytes, r)
        if dpf == nil {
            log("unable to open patch file d")
            throw BRBSPatchError.Unknown
        }
        let dpfseek = fseeko(dpf, 32 + bzCrtlLen, SEEK_SET)
        if dpfseek != 0 {
            log("unable to seek patch file d: \(dpfseek)")
            throw BRBSPatchError.Unknown
        }
        let dbz2err = UnsafeMutablePointer<Int32>.alloc(1)
        let dpfbz2 = BZ2_bzReadOpen(dbz2err, dpf, 0, 0, nil, 0)
        if dpfbz2 == nil {
            log("unable to bzopen patch file d: \(dbz2err)")
            throw BRBSPatchError.Unknown
        }
        let epf = fopen(patchFilePathBytes, r)
        if epf == nil {
            log("unable to open patch file e")
            throw BRBSPatchError.Unknown
        }
        let epfseek = fseeko(epf, 32 + bzCrtlLen + bzDataLen, SEEK_SET)
        if epfseek != 0 {
            log("unable to seek patch file e: \(epfseek)")
            throw BRBSPatchError.Unknown
        }
        let ebz2err = UnsafeMutablePointer<Int32>.alloc(1)
        let epfbz2 = BZ2_bzReadOpen(ebz2err, epf, 0, 0, nil, 0)
        if epfbz2 == nil {
            log("unable to bzopen patch file e: \(ebz2err)")
            throw BRBSPatchError.Unknown
        }
        
        guard let oldData = NSData(contentsOfFile: oldFilePath) else {
            log("unable to read old file path")
            throw BRBSPatchError.Unknown
        }
        let old = UnsafePointer<CUnsignedChar>(oldData.bytes)
        let oldSize = off_t(oldData.length)
        var oldPos: off_t = 0, newPos: off_t = 0
        let new = UnsafeMutablePointer<CUnsignedChar>(malloc(Int(newSize) + 1))
        let buf = UnsafeMutablePointer<CUnsignedChar>(malloc(8))
        var crtl = Array<off_t>(count: 3, repeatedValue: 0)
        while newPos < newSize {
            // read control data
            for i in 0...2 {
                let lenread = BZ2_bzRead(cbz2err, cpfbz2, buf, 8)
                if (lenread < 8) || ((cbz2err.memory != BZ_OK) && (cbz2err.memory != BZ_STREAM_END)) {
                    log("unable to read control data \(lenread) \(cbz2err.memory)")
                    throw BRBSPatchError.CorruptPatch
                }
                crtl[i] = offtin(UnsafePointer<CUnsignedChar>(buf))
            }
            // sanity check
            if (newPos + crtl[0]) > newSize {
                log("incorrect size of crtl[0]")
                throw BRBSPatchError.CorruptPatch
            }
            
            // read diff string
            let dlenread = BZ2_bzRead(dbz2err, dpfbz2, new + Int(newPos), Int32(crtl[0]))
            if (dlenread < Int32(crtl[0])) || ((dbz2err.memory != BZ_OK) && (dbz2err.memory != BZ_STREAM_END)) {
                log("unable to read diff string \(dlenread) \(dbz2err.memory)")
                throw BRBSPatchError.CorruptPatch
            }
            
            // add old data to diff string
            if crtl[0] > 0 {
                for i in 0...(Int(crtl[0]) - 1) {
                    if (oldPos + i >= 0) && (oldPos + i < oldSize) {
                        let np = Int(newPos) + i, op = Int(oldPos) + i
                        new[np] = new[np] &+ old[op]
                    }
                }
            }
            
            // adjust pointers
            newPos += crtl[0]
            oldPos += crtl[0]
            
            // sanity check
            if (newPos + crtl[1]) > newSize {
                log("incorrect size of crtl[1]")
                throw BRBSPatchError.CorruptPatch
            }
            
            // read extra string
            let elenread = BZ2_bzRead(ebz2err, epfbz2, new + Int(newPos), Int32(crtl[1]))
            if (elenread < Int32(crtl[1])) || ((ebz2err.memory != BZ_OK) && (ebz2err.memory != BZ_STREAM_END)) {
                log("unable to read extra string \(elenread) \(ebz2err.memory)")
                throw BRBSPatchError.CorruptPatch
            }
            
            // adjust pointers
            newPos += crtl[1]
            oldPos += crtl[2]
        }
        
        // clean up bz2 reads 
        BZ2_bzReadClose(cbz2err, cpfbz2)
        BZ2_bzReadClose(dbz2err, dpfbz2)
        BZ2_bzReadClose(ebz2err, epfbz2)
        
        if (fclose(cpf) != 0) || (fclose(dpf) != 0) || (fclose(epf) != 0) {
            log("unable to close bzip file handles")
            throw BRBSPatchError.Unknown
        }
        
        // write out new file
        let fm = NSFileManager.defaultManager()
        if fm.fileExistsAtPath(newFilePath) {
            try fm.removeItemAtPath(newFilePath)
        }
        let newData = NSData(bytes: new, length: Int(newSize))
        try newData.writeToFile(newFilePath, options: .DataWritingAtomic)
        return new
    }
    
    static private func log(string: String) {
        if patchLogEnabled {
            print("[BRBSPatch] \(string)")
        }
    }
}

enum BRHTTPServerError: ErrorType {
    case SocketCreationFailed
    case SocketBindFailed
    case SocketListenFailed
    case SocketRecvFailed
    case SocketWriteFailed
    case InvalidHttpRequest
    case InvalidRangeHeader
}

@objc public protocol BRHTTPMiddleware {
    func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void)
}

@objc public class BRHTTPMiddlewareResponse: NSObject {
    var request: BRHTTPRequest
    var response: BRHTTPResponse?
    
    init(request: BRHTTPRequest, response: BRHTTPResponse?) {
        self.request = request
        self.response = response
    }
}

@objc public class BRHTTPServer: NSObject {
    var fd: Int32 = -1
    var clients: Set<Int32> = []
    var path: NSURL
    var debugURL: NSURL?
    var middleware: [BRHTTPMiddleware] = [BRHTTPMiddleware]()
    
    init(baseDirectory: NSURL) {
        path = baseDirectory
        middleware.append(BRHTTPFileMiddleware(baseURL: baseDirectory))
        super.init()
    }
    
    // call debugFrom(NSURL(string: "BASE_URL")) to proxy assets from a debug server, instead of serving them from a 
    // local directory. use this when developing by starting a local server pointing to your dev assets that would
    // normally be in the bundle
    func debugFrom(URL: NSURL?) {
        debugURL = URL
        for mw in middleware {
            if let fmw = mw as? BRHTTPFileMiddleware {
                fmw.debugURL = URL
            }
        }
    }
    
    func prependMiddleware(middleware mw: BRHTTPMiddleware) {
        middleware.insert(mw, atIndex: 0)
    }
    
    func appendMiddleware(middle mw: BRHTTPMiddleware) {
        middleware.append(mw)
    }
    
    func start(port: in_port_t = 8888, maxPendingConnections: Int32 = SOMAXCONN) throws {
        stop()
        
        let sfd = socket(AF_INET, SOCK_STREAM, 0)
        if sfd == -1 {
            throw BRHTTPServerError.SocketCreationFailed
        }
        var v: Int32 = 1
        if setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, &v, socklen_t(sizeof(Int32))) == -1 {
            Darwin.shutdown(sfd, SHUT_RDWR)
            close(sfd)
            throw BRHTTPServerError.SocketCreationFailed
        }
        v = 1
        setsockopt(sfd, SOL_SOCKET, SO_NOSIGPIPE, &v, socklen_t(sizeof(Int32)))
        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(sizeof(sockaddr_in))
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Int(OSHostByteOrder()) == OSLittleEndian ? _OSSwapInt16(port) : port
        addr.sin_addr = in_addr(s_addr: inet_addr("0.0.0.0"))
        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0 ,0)
        
        var bind_addr = sockaddr()
        memcpy(&bind_addr, &addr, Int(sizeof(sockaddr_in)))
        
        if bind(sfd, &bind_addr, socklen_t(sizeof(sockaddr_in))) == -1 {
            Darwin.shutdown(sfd, SHUT_RDWR)
            close(sfd)
            throw BRHTTPServerError.SocketBindFailed
        }
        
        if listen(sfd, maxPendingConnections) == -1 {
            Darwin.shutdown(sfd, SHUT_RDWR)
            close(sfd)
            throw BRHTTPServerError.SocketListenFailed
        }
        
        fd = sfd
        acceptClients()
        NSLog("Serving \(path) on \(port)")
    }
    
    func stop() {
        Darwin.shutdown(fd, SHUT_RDWR)
        close(fd)
        fd = -1
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        for cli_fd in self.clients {
            Darwin.shutdown(cli_fd, SHUT_RDWR)
        }
        self.clients.removeAll(keepCapacity: true)
    }
    
    func addClient(cli_fd: Int32) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        clients.insert(cli_fd)
    }
    
    func rmClient(cli_fd: Int32) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        clients.remove(cli_fd)
    }
    
    private func acceptClients() {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) { () -> Void in
            while true {
                var addr = sockaddr(sa_len: 0, sa_family: 0, sa_data: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
                var len: socklen_t = 0
                let cli_fd = accept(self.fd, &addr, &len)
                if cli_fd == -1 {
                    break
                }
                var v: Int32 = 1
                setsockopt(cli_fd, SOL_SOCKET, SO_NOSIGPIPE, &v, socklen_t(sizeof(Int32)))
                self.addClient(cli_fd)
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) { () -> Void in
                    while let req = try? BRHTTPRequestImpl(readFromFd: cli_fd) {
                        self.dispatch(middleware: self.middleware, req: req)
                        if !req.isKeepAlive { break }
                    }
                    Darwin.shutdown(cli_fd, SHUT_RDWR)
                    close(cli_fd)
                    self.rmClient(cli_fd)
                }
            }
            self.stop()
        }
    }
    
    private func dispatch(var middleware mw: [BRHTTPMiddleware], req: BRHTTPRequest) {
        if let curMw = mw.popLast() {
            curMw.handle(req, next: { (mwResp) -> Void in
                if let httpResp = mwResp.response {
                    do {
                        try httpResp.send()
                    } catch let e {
                        print("[BRHTTPServer] error sending response. request: \(req) error: \(e)")
                    }
                } else {
                    self.dispatch(middleware: mw, req: mwResp.request)
                }
            })
        } else {
            print("[BRHTTPServer] did not send a response")
            _ = try? BRHTTPResponse(
                request: req, statusCode: 404, statusReason: "Not Found", headers: nil, body: nil).send()
        }
    }
}

@objc public protocol BRHTTPRequest {
    var fd: Int32 { get }
    var method: String { get }
    var path: String { get }
    var queryString: String { get }
    var query: [String: [String]] { get }
    var headers: [String: [String]] { get }
    var isKeepAlive: Bool { get }
    func body() -> NSData?
    var hasBody: Bool { get }
    var contentType: String { get }
    var contentLength: Int { get }
}

@objc public class BRHTTPRequestImpl: NSObject, BRHTTPRequest {
    public var fd: Int32
    public var method: String = "GET"
    public var path: String = "/"
    public var queryString: String = ""
    public var query: [String: [String]] = [String: [String]]()
    public var headers: [String: [String]] = [String: [String]]()
    
    public var isKeepAlive: Bool {
        return (headers["connection"] != nil
            && headers["connection"]?.count > 0
            && headers["connection"]![0] == "keep-alive")
    }
    
    static let rangeRe = try! NSRegularExpression(pattern: "bytes=(\\d*)-(\\d*)", options: .CaseInsensitive)
    
    init(readFromFd: Int32) throws {
        fd = readFromFd
        super.init()
        let status = try readLine()
        let statusParts = status.componentsSeparatedByString(" ")
        if statusParts.count < 3 {
            throw BRHTTPServerError.InvalidHttpRequest
        }
        method = statusParts[0]
        path = statusParts[1]
        // parse query string
        if path.rangeOfString("?") != nil {
            let parts = path.componentsSeparatedByString("?")
            path = parts[0]
            queryString = parts[1..<parts.count].joinWithSeparator("?")
            let pairs = queryString.componentsSeparatedByString("&")
            for pair in pairs {
                let pairSides = pair.componentsSeparatedByString("=")
                if pairSides.count == 2 {
                    if query[pairSides[0]] != nil {
                        query[pairSides[0]]?.append(pairSides[1])
                    } else {
                        query[pairSides[0]] = [pairSides[1]]
                    }
                }
            }
        }
        // parse headers
        while true {
            let hdr = try readLine()
            if hdr.isEmpty { break }
            let hdrParts = hdr.componentsSeparatedByString(":")
            if hdrParts.count >= 2 {
                let name = hdrParts[0].lowercaseString
                let hdrVal = hdrParts[1..<hdrParts.count].joinWithSeparator(":").stringByTrimmingCharactersInSet(
                    NSCharacterSet.whitespaceCharacterSet())
                if headers[name] != nil {
                    headers[name]?.append(hdrVal)
                } else {
                    headers[name] = [hdrVal]
                }
            }
        }
    }
    
    func readLine() throws -> String {
        var chars: String = ""
        var n = 0
        repeat {
            n = self.read()
            if (n > 13 /* CR */) { chars.append(Character(UnicodeScalar(n))) }
        } while n > 0 && n != 10 /* NL */
        if n == -1 {
            throw BRHTTPServerError.SocketRecvFailed
        }
        return chars
    }
    
    func read() -> Int {
        var buf = [UInt8](count: 1, repeatedValue: 0)
        let n = recv(fd, &buf, 1, 0)
        if n <= 0 {
            return n
        }
        return Int(buf[0])
    }
    
    public var hasBody: Bool {
        return method == "POST" || method == "PATCH" || method == "PUT"
    }
    
    public var contentLength: Int {
        if let hdrs = headers["content-length"] where hasBody && hdrs.count > 0 {
            if let i = Int(hdrs[0]) {
                return i
            }
        }
        return 0
    }
    
    public var contentType: String {
        if let hdrs = headers["content-type"] where hdrs.count > 0 { return hdrs[0] }
        return "application/octet-stream"
    }
    
    private var _body: [UInt8]?
    private var _bodyRead: Bool = false
    
    public func body() -> NSData? {
        if _bodyRead && _body != nil {
            return NSData(bytesNoCopy: UnsafeMutablePointer(_body!), length: contentLength)
        }
        if _bodyRead {
            return nil
        }
        var buf = [UInt8](count: contentLength, repeatedValue: 0)
        let n = recv(fd, &buf, contentLength, 0)
        if n <= 0 {
            _bodyRead = true
            return nil
        }
        _body = buf
        return NSData(bytesNoCopy: UnsafeMutablePointer(_body!), length: contentLength)
    }
    
    func rangeHeader() throws -> (Int, Int)? {
        if headers["range"] == nil {
            return nil
        }
        guard let rngHeader = headers["range"]?[0],
            match = BRHTTPRequestImpl.rangeRe.matchesInString(rngHeader, options: .Anchored, range:
                NSRange(location: 0, length: rngHeader.characters.count)).first
            where match.numberOfRanges == 3 else {
                throw BRHTTPServerError.InvalidRangeHeader
        }
        let startStr = (rngHeader as NSString).substringWithRange(match.rangeAtIndex(1))
        let endStr = (rngHeader as NSString).substringWithRange(match.rangeAtIndex(2))
        guard let start = Int(startStr), end = Int(endStr) else {
            throw BRHTTPServerError.InvalidRangeHeader
        }
        return (start, end)
    }
}

@objc public class BRHTTPResponse: NSObject {
    var request: BRHTTPRequest
    var statusCode: Int?
    var statusReason: String?
    var headers: [String: [String]]?
    var body: [UInt8]?
    
    static var reasonMap: [Int: String] = [
        201: "No Content",
        404: "Not Found",
        500: "Internal Server Error"
    ]
    
    init(request: BRHTTPRequest, statusCode: Int?, statusReason: String?, headers: [String: [String]]?, body: [UInt8]?) {
        self.request = request
        self.statusCode = statusCode
        self.statusReason = statusReason
        self.headers = headers
        self.body = body
        super.init()
    }
    
    convenience init(request: BRHTTPRequest, code: Int) {
        self.init(request: request, statusCode: code, statusReason: BRHTTPResponse.reasonMap[code], headers: nil, body: nil)
    }
    
    func send() throws {
        let status = statusCode ?? 200
        let reason = statusReason ?? "OK"
        try writeUTF8("HTTP/1.1 \(status) \(reason)\r\n")
        
        let length = body?.count ?? 0
        try writeUTF8("Content-Length: \(length)\r\n")
        if request.isKeepAlive {
            try writeUTF8("Connection: keep-alive\r\n")
        }
        let hdrs = headers ?? [String: [String]]()
        for (n, v) in hdrs {
            for yv in v {
                try writeUTF8("\(n): \(yv)\r\n")
            }
        }
        
        try writeUTF8("\r\n")
        
        if let b = body {
            try writeUInt8(b)
        }
    }
    
    private func writeUTF8(s: String) throws {
        try writeUInt8([UInt8](s.utf8))
    }
    
    private func writeUInt8(data: [UInt8]) throws {
        try data.withUnsafeBufferPointer { pointer in
            var sent = 0
            while sent < data.count {
                let s = write(request.fd, pointer.baseAddress + sent, Int(data.count - sent))
                if s <= 0 {
                    throw BRHTTPServerError.SocketWriteFailed
                }
                sent += s
            }
        }
    }
}

@objc public class BRHTTPFileMiddleware: NSObject, BRHTTPMiddleware {
    var baseURL: NSURL!
    var debugURL: NSURL?
    
    init(baseURL: NSURL, debugURL: NSURL? = nil) {
        super.init()
        self.baseURL = baseURL
        self.debugURL = debugURL
    }
    
    public func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void) {
        var fileURL: NSURL!
        if debugURL == nil {
            let reqPath = request.path.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "/"))
            fileURL = baseURL.URLByAppendingPathComponent(reqPath)
        } else {
            var reqPath = request.path
            if (debugURL!.path!.hasSuffix("/")) {
                reqPath = reqPath.substringFromIndex(reqPath.startIndex.advancedBy(1))
            }
            fileURL = debugURL!.URLByAppendingPathComponent(reqPath)
        }
        
        guard let body = NSData(contentsOfURL: fileURL) else {
            return next(BRHTTPMiddlewareResponse(request: request, response: nil))
        }
        NSLog("GET \(fileURL)")
        NSLog("Detected content type: \(detectContentType(URL: fileURL))")
        
        do {
            let privReq = request as! BRHTTPRequestImpl
            let rangeHeader = try privReq.rangeHeader()
            if rangeHeader != nil {
                let (end, start) = rangeHeader!
                let length = end - start
                let range = NSRange(location: start, length: length + 1)
                guard range.location + range.length <= body.length else {
                    let r =  BRHTTPResponse(
                        request: request, statusCode: 418, statusReason: "Request Range Not Satisfiable",
                        headers: nil, body: nil)
                    return next(BRHTTPMiddlewareResponse(request: request, response: r))
                }
                let subDat = body.subdataWithRange(range)
                let headers = [
                    "Content-Range": ["bytes \(start)-\(end)/\(body.length)"],
                    "Content-Type": [detectContentType(URL: fileURL)]
                ]
                var ary = [UInt8](count: subDat.length, repeatedValue: 0)
                subDat.getBytes(&ary, length: subDat.length)
                let r =  BRHTTPResponse(
                    request: request, statusCode: 200, statusReason: "OK", headers: headers, body: ary)
                return next(BRHTTPMiddlewareResponse(request: request, response: r))
            }
        } catch {
            let r = BRHTTPResponse(
                request: request, statusCode: 400, statusReason: "Bad Request", headers: nil,
                body: [UInt8]("Invalid Range Header".utf8))
            return next(BRHTTPMiddlewareResponse(request: request, response: r))
        }
        
        var ary = [UInt8](count: body.length, repeatedValue: 0)
        body.getBytes(&ary, length: body.length)
        let r = BRHTTPResponse(request: request, statusCode: 200, statusReason: "OK",
            headers: ["Content-Type": [detectContentType(URL: fileURL)]], body: ary)
        return next(BRHTTPMiddlewareResponse(request: request, response: r))
    }
    
    private func detectContentType(URL url: NSURL) -> String {
        if let ext = url.pathExtension {
            switch ext {
            case "ttf":
                return "application/font-truetype"
            case "woff":
                return "application/font-woff"
            case "otf":
                return "application/font-opentype"
            case "svg":
                return "image/svg+xml"
            case "html":
                return "text/html"
            case "png":
                return "image/png"
            case "jpeg", "jpg":
                return "image/jpeg"
            case "css":
                return "text/css"
            case "js":
                return "application/javascript"
            case "json":
                return "application/json"
            default: break
            }
        }
        return "application/octet-stream"
    }
}

public typealias BRHTTPRouteMatch = [String: [String]]

public typealias BRHTTPRoute = (request: BRHTTPRequest, match: BRHTTPRouteMatch) -> BRHTTPResponse

@objc public class BRHTTPRoutePair: NSObject {
    public var method: String = "GET"
    public var path: String = "/"
    public var regex: NSRegularExpression!
    var captureGroups: [Int: String]!
    
    override public var hashValue: Int {
        return method.hashValue ^ path.hashValue
    }
    
    init(method m: String, path p: String) {
        method = m.uppercaseString
        path = p
        super.init()
        parse()
    }
    
    private func parse() {
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        if path.hasSuffix("/") {
            path = path.substringToIndex(path.endIndex.advancedBy(-1))
        }
        let parts = path.componentsSeparatedByString("/")
        captureGroups = [Int: String]()
        var reParts = [String]()
        var i = 0
        for part in parts {
            if part.hasPrefix("(") && part.hasSuffix(")") {
                let wcRange = Range(start: part.endIndex.advancedBy(-2), end: part.endIndex.advancedBy(-1))
                if part.substringWithRange(wcRange) == "*" { // a wild card capture (part*)
                    captureGroups[i] = part.substringWithRange(
                        Range(start: part.startIndex.advancedBy(1), end: part.endIndex.advancedBy((-2))))
                    reParts.append("(.*)")
                } else {
                    captureGroups[i] = part.substringWithRange(
                        Range(start: part.startIndex.advancedBy(1), end: part.endIndex.advancedBy(-1)))
                    reParts.append("([^/]+)") // a capture (part)
                }
                i++
            } else {
                reParts.append(part) // a non-captured component
            }
        }

        let re = "^" + reParts.joinWithSeparator("/") + "$"
        //print("\n\nroute: \n\n method: \(method)\n path: \(path)\n regex: \(re)\n captures: \(captureGroups)\n\n")
        regex = try! NSRegularExpression(pattern: re, options: [])
    }
    
    public func match(request: BRHTTPRequest) -> BRHTTPRouteMatch? {
        if request.method.uppercaseString != method {
            return nil
        }
        var p = request.path as NSString // strip trailing slash
        if p.hasSuffix("/") { p = request.path.substringToIndex(request.path.endIndex.advancedBy(-1)) }
        if let m = regex.firstMatchInString(request.path, options: [], range: NSMakeRange(0, p.length))
        where m.numberOfRanges - 1 == captureGroups.count {
            var match = BRHTTPRouteMatch()
            for i in 1..<m.numberOfRanges {
                let key = captureGroups[i-1]!
                let captured = p.substringWithRange(m.rangeAtIndex(i))
                if match[key] == nil {
                    match[key] = [captured]
                } else {
                    match[key]?.append(captured)
                }
                //print("capture range: '\(key)' = '\(captured)'\n\n")
            }
            return match
        }
        return nil
    }
}

@objc public class BRHTTPRouter: NSObject, BRHTTPMiddleware {
    var routes: [BRHTTPRoutePair: BRHTTPRoute] = [BRHTTPRoutePair: BRHTTPRoute]()
    
    public func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void) {
        var response: BRHTTPResponse? = nil
        
        for (routePair, route) in routes {
            if let match = routePair.match(request) {
                response = route(request: request, match: match)
                break
            }
        }
        
        return next(BRHTTPMiddlewareResponse(request: request, response: response))
    }
    
    public func get(pattern: String, route: BRHTTPRoute) {
        routes[BRHTTPRoutePair(method: "GET", path: pattern)] = route
    }
    
    public func post(pattern: String, route: BRHTTPRoute) {
        routes[BRHTTPRoutePair(method: "POST", path: pattern)] = route
    }
    
    public func put(pattern: String, route: BRHTTPRoute) {
        routes[BRHTTPRoutePair(method: "PUT", path: pattern)] = route
    }
    
    public func patch(pattern: String, route: BRHTTPRoute) {
        routes[BRHTTPRoutePair(method: "PATCH", path: pattern)] = route
    }
    
    public func delete(pattern: String, route: BRHTTPRoute) {
        routes[BRHTTPRoutePair(method: "DELETE", path: pattern)] = route
    }
    
    public func any(pattern: String, route: BRHTTPRoute) {
        for m in ["GET", "POST", "PUT", "PATCH", "DELETE"] {
            routes[BRHTTPRoutePair(method: m, path: pattern)] = route
        }
    }
}

@objc public class BRAPIProxy: NSObject, BRHTTPMiddleware {
    var mountPoint: String
    var apiInstance: BRAPIClient
    var shouldVerifyHeader: String = "x-should-verify"
    var shouldAuthHeader: String = "x-should-authenticate"
    
    var bannedSendHeaders: [String] {
        return [
            shouldVerifyHeader,
            shouldAuthHeader,
            "connection",
            "authorization"
        ]
    }
    
    var bannedReceiveHeaders: [String] = ["content-length", "connection"]
    
    init(mountAt: String, client: BRAPIClient) {
        mountPoint = mountAt
        if mountPoint.hasSuffix("/") {
            mountPoint = mountPoint.substringToIndex(mountPoint.endIndex.advancedBy(-1))
        }
        apiInstance = client
        super.init()
    }
    
    public func handle(request: BRHTTPRequest, next: (BRHTTPMiddlewareResponse) -> Void) {
        if request.path.hasPrefix(mountPoint) {
            let path = request.path.substringFromIndex(request.path.startIndex.advancedBy(mountPoint.characters.count))
            let nsReq = NSMutableURLRequest(URL: apiInstance.url(path))
            // copy body
            if request.hasBody {
                nsReq.HTTPBody = request.body()
            }
            // copy headers
            for (hdrName, hdrs) in request.headers {
                if bannedSendHeaders.contains(hdrName) { continue }
                for hdr in hdrs {
                    nsReq.setValue(hdr, forHTTPHeaderField: hdrName)
                }
            }
            
            var verify = false, auth = false
            if let verifyHeader = request.headers[shouldVerifyHeader] where verifyHeader.count > 0 {
                if verifyHeader[0].lowercaseString == "yes" {
                    verify = true
                }
            }
            if let authHeader = request.headers[shouldAuthHeader] where authHeader.count > 0 {
                if authHeader[0].lowercaseString == "yes" {
                    auth = true
                }
            }
            apiInstance.dataTaskWithRequest(nsReq, authenticated: auth, verify: verify, retryCount: 0, handler:
                { (nsData, nsHttpResponse, nsError) -> Void in
                    if let httpResp = nsHttpResponse {
                        var hdrs = [String: [String]]()
                        for (k, v) in httpResp.allHeaderFields {
                            if self.bannedReceiveHeaders.contains((k as! String).lowercaseString) { continue }
                            hdrs[k as! String] = [v as! String]
                        }
                        var body: [UInt8]? = nil
                        if let bod = nsData {
                            let b = UnsafeBufferPointer<UInt8>(start: UnsafePointer(bod.bytes), count: bod.length)
                            body = Array(b)
                        }
                        let resp = BRHTTPResponse(
                            request: request, statusCode: httpResp.statusCode,
                            statusReason: NSHTTPURLResponse.localizedStringForStatusCode(httpResp.statusCode),
                            headers: hdrs, body: body)
                        return next(BRHTTPMiddlewareResponse(request: request, response: resp))
                    } else {
                        print("[BRAPIProxy] error getting response from backend: \(nsError)")
                        return next(BRHTTPMiddlewareResponse(request: request, response: nil))
                    }
                }).resume()
        } else {
            return next(BRHTTPMiddlewareResponse(request: request, response: nil))
        }
    }
}
