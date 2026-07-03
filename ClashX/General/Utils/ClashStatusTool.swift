//
//  ClashStatusTool.swift
//  ClashX Pro
//
//  Created by yicheng on 2020/4/28.
//  Copyright © 2020 west2online. All rights reserved.
//

import Cocoa

actor ClashStatusTool {
    @MainActor private var retryCount: Int = 0

    @MainActor
    func checkPortConfig(cfg: ClashConfig?) async {
        guard let cfg,
              ConfigManager.shared.kernelState.isOperational else {
            retryCount = 0
            return
        }
        guard cfg.usedHttpPort == 0 else {
            retryCount = 0
            return
        }

        if retryCount >= 4 {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("ClashX Start Error!", comment: "")
            alert.informativeText = NSLocalizedString("Ports Open Fail, Please try to restart ClashX", comment: "")
            alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
            alert.addButton(withTitle: "Edit Config")
            let ret = alert.runModal()
            if ret == .alertSecondButtonReturn {
                NSWorkspace.shared.openFilePath(Paths.localConfigPath(for: "config"))
            }
            retryCount = 0
            ExitManager.shared.requestQuit(force: true)
        } else {
            retryCount += 1
            try? await Task.sleep(seconds: 1)
            await ConfigReloadManager.shared.syncConfig()
        }
    }
}
