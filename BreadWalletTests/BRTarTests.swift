//
//  BRTarTests.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 12/1/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

import XCTest
@testable import breadwallet

class BRTarTests: XCTestCase {
    var fileUrl: NSURL?
    
    override func setUp() {
        // download a test tar file
        let fm = NSFileManager.defaultManager()
        let url = NSURL(string: "https://s3.amazonaws.com/breadwallet-assets/bread-buy/7f5bc5c6cc005df224a6ea4567e508491acaffdc2e4769e5262a52f5b785e261.tar")!
        let documentsUrl =  fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
        let destinationUrl = documentsUrl.URLByAppendingPathComponent(url.lastPathComponent!)
        if fm.fileExistsAtPath(destinationUrl.path!) {
            print("file already exists [\(destinationUrl.path!)]")
            fileUrl = destinationUrl
        } else if let dataFromURL = NSData(contentsOfURL: url){
            if dataFromURL.writeToURL(destinationUrl, atomically: true) {
                print("file saved [\(destinationUrl.path!)]")
                fileUrl = destinationUrl
            } else {
                XCTFail("error saving file")
            }
        } else {
            XCTFail("error downloading file")
        }
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testExtractTar() {
        guard let fileUrl = fileUrl else { XCTFail("file url not defined"); return }
        let fm = NSFileManager.defaultManager()
        let docsPath = fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first!
        let destPath = docsPath.URLByAppendingPathComponent("extracted_files")
        do {
            try BRTar.createFilesAndDirectoriesAtPath(destPath.path!, withTarPath: fileUrl.path!)
        } catch let e {
            XCTFail("failed to extract tar file with \(e)")
        }
    }
    
//    func testPerformanceExample() {
//        self.measureBlock {
//        }
//    }
    
}
