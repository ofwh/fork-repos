//
//  TunModeSettingCommand.swift
//  ClashX.Meta
//
//  Created by hbsgithub on 2023/5/26.
//  Copyright © 2023 west2online. All rights reserved.
//

import Foundation
import AppKit

@objc class TunModeSettingCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            let current = ProxyManager.shared.state.intent.tunEnabled
            await ProxyManager.shared.setTunEnabled(!current)
        }
        return nil
    }
}
