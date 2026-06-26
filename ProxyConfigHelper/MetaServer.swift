//
//  MetaServer.swift
//  ClashX
//
//  Copyright © 2024 west2online. All rights reserved.
//

import Cocoa

let kCoreLogName = "clashx_mihomo.log"
let kCoreCrashLogName = "clashx_mihomo_error.log"

struct MetaServer: Codable {
	var externalController: String
	let secret: String
	var log: String = ""
	
    var safePaths = ""
    var sessionId = ""
    
	func jsonString() -> String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .prettyPrinted

		guard let data = try? encoder.encode(self),
			  let string = String(data: data, encoding: .utf8) else {
			return ""
		}
		return string
	}
}
