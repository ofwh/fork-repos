//
//  ClashStatusTool.swift
//  ClashX Pro
//
//  Created by yicheng on 2020/4/28.
//  Copyright © 2020 west2online. All rights reserved.
//

import Cocoa

actor ClashStatusTool {
    @MainActor private var lastPortWasZero: Date?

    @MainActor
    func checkPortConfig(cfg: ClashConfig?) async {
        guard let cfg,
              ConfigManager.shared.kernelState.isOperational else {
            lastPortWasZero = nil
            return
        }
        Logger.log("mixedPort: \(cfg.mixedPort) ", level: .info)
        
        guard cfg.usedHttpPort == 0 else {
            lastPortWasZero = nil
            return
        }
        
        if let time = lastPortWasZero?.timeIntervalSinceNow, time < -1 {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("ClashX Start Error!", comment: "")
            alert.informativeText = NSLocalizedString("Ports Open Fail, Please try to restart ClashX", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
            alert.addButton(withTitle: "Edit Config")
            let ret = alert.runModal()
            if ret == .alertSecondButtonReturn {
                NSWorkspace.shared.openFilePath(Paths.localConfigPath(for: "config"))
            }
            NSApp.terminate(nil)
        } else if lastPortWasZero == nil {
            Logger.log("resync Config", level: .error)
            
            lastPortWasZero = Date()
            try? await Task.sleep(seconds: 1)
            await ConfigReloadManager.shared.syncConfig()
        }
    }
}
