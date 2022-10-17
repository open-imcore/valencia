//
//  GSABag.swift
//  ValenciaKit
//
//  Created by Eric Rabil on 10/23/22.
//  Copyright © 2022 tuist.io. All rights reserved.
//

import Foundation

struct GSA {}

extension GSA {
    struct Header {
        static let clientInfo = "X-MMe-Client-Info"
        static let country = "X-MMe-Country"
    }
}

class GSABag {
    class Fetcher {
        static let lookupURL = URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!
        static let lookupURLV2 = lookupURL.appendingPathComponent("v2")
    }
}
