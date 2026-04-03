//
//  UpdateConfigAction.swift
//  ClashX
//
//  Created by yicheng on 2023/9/5.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Foundation

enum UpdateConfigAction {
    static func showError(text: String, configName: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = NSLocalizedString("Reload Config Fail", comment: "")
        alert.informativeText = text
        alert.addButton(withTitle: NSLocalizedString("Edit in Text Mode", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Task { @MainActor in
                guard let path = await ConfigManager.getConfigPath(configName: configName) else { return }
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        }
    }
}
