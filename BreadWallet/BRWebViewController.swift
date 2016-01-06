//
//  BRWebViewController.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 12/10/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import Foundation
import UIKit
import WebKit

    
@available(iOS 9.0, *)
@objc public class BRWebViewController : UIViewController {
    var wkProcessPool: WKProcessPool
    var webView: WKWebView?
    var bundleName: String
    var server: BRHTTPServer?
    
    init(bundleName name: String) {
        wkProcessPool = WKProcessPool()
        bundleName = name
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func loadView() {
        let config = WKWebViewConfiguration()
        config.processPool = wkProcessPool
        config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore()
        config.allowsInlineMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        config.requiresUserActionForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        
        server = BRAPIClient.sharedClient.serveBundle("bread-buy", debugURL: "http://localhost:4200")
        setupIntegrations()
//        server = BRAPIClient.sharedClient.serveBundle("bread-buy")
        let indexUrl = NSURL(string: "http://localhost:8888/index.html")!
        let request = NSURLRequest(URL: indexUrl)
        
        view = UIView(frame: CGRectZero)
        view.backgroundColor = UIColor(red:0.98, green:0.98, blue:0.98, alpha:1.0)
        
        webView = WKWebView(frame: CGRectZero, configuration: config)
        webView?.backgroundColor = UIColor(red:0.98, green:0.98, blue:0.98, alpha:1.0)
        webView?.loadRequest(request)
        webView?.autoresizingMask = [UIViewAutoresizing.FlexibleHeight, UIViewAutoresizing.FlexibleWidth]
        view.addSubview(webView!)
    }
    
    override public func viewWillAppear(animated: Bool) {
        edgesForExtendedLayout = .All
    }
    
    private func closeNow() {
        dismissViewControllerAnimated(true, completion: nil)
    }
    
    private func setupIntegrations() {
        // proxy api for signing and verification
        let apiProxy = BRAPIProxy(mountAt: "/_api", client: BRAPIClient.sharedClient)
        server?.prependMiddleware(middleware: apiProxy)
        
        // http router for native functionality
        let router = BRHTTPRouter()
        server?.prependMiddleware(middleware: router)
        
        // GET /_close closes the browser modal
        router.get("/_close") { (request, match) -> BRHTTPResponse in
            self.closeNow()
            return BRHTTPResponse(request: request, code: 201)
        }
    }
    
    public func preload() {
        _ = self.view // force webview loading
    }
}

