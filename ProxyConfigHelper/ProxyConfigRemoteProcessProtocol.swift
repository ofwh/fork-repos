//
//  ProxyConfigRemoteProcessProtocol.swift
//  com.metacubex.ClashX.ProxyConfigHelper
//
//  Copyright © 2024 west2online. All rights reserved.
//

import Foundation

@objc(ProxyConfigRemoteProcessProtocol)
protocol ProxyConfigRemoteProcessProtocol {
	func sendRequest(_ request: Data, reply: @escaping (Data?, NSString?) -> Void)
}
