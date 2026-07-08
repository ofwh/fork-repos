//
//  ProxySettingCommand.swift
//  ClashX.Meta
//
//  Created by Vince-hz on 2022/1/25.
//  Copyright © 2022 west2online. All rights reserved.
//

import AppKit
import Foundation

@objc class ProxySettingCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            let current = ProxyManager.shared.state.intent.systemProxyEnabled
            await ProxyManager.shared.setSystemProxyEnabled(!current)
        }
        return nil
    }
}
