//
//  TerminalCleanUpAction.swift
//  ClashX
//
//  Created by yicheng on 2023/9/5.
//  Copyright © 2023 west2online. All rights reserved.
//

import AppKit
import Foundation
import RxSwift

enum TerminalConfirmAction {
    @MainActor
    static func run(app: NSApplication) async {
        guard confirmAction() else {
            await replyShouldCancelTermination(app: app)
            return
        }

        ConfigManager.shared.restoreTunProxy = ConfigManager.shared.isTunModeVariable.value

        async let stopMetaAndDisableTunTask = stopMetaAndDisableTun()

        removeTempFiles()

        guard let forceDisable = forceDisableForProxyCleanup() else {
            _ = await stopMetaAndDisableTunTask
            ConfigManager.shared.restoreSystemProxy = false
            Logger.log("ClashX quit without clean waiting")
            await replyShouldTerminate(app: app, initialDelay: 0)
            return
        }

        Logger.log("ClashX quit need clean proxy setting")
        ConfigManager.shared.restoreSystemProxy = true

        prepareForTerminationWait()

        _ = await stopMetaAndDisableTunTask
        Logger.log("ClashX quit wait for clean up")
        let finished = await performProxyCleanup(forceDisable: forceDisable)
        if finished {
            Logger.log("ClashX quit after clean up finish")
            await replyShouldTerminate(app: app, initialDelay: 0.2)
        } else {
            Logger.log("ClashX quit after clean up timeout")
            await replyShouldTerminate(app: app, initialDelay: 0)
        }
    }

    private static func stopMetaAndDisableTun() async {
        try? await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.StopMeta())
        try? await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.UpdateTun(state: false, dns: ConfigManager.metaTunDNS))
    }

    private static func removeTempFiles() {
        try? FileManager.default.removeItem(atPath: Paths.tempPath() + "/cacheConfigs")
        try? FileManager.default.removeItem(atPath: Paths.localConfigPath(for: kSafeConfigName))
    }

    private static func forceDisableForProxyCleanup() -> Bool? {
        let shouldCleanSystemProxy =
            (ConfigManager.shared.proxyPortAutoSet && !ConfigManager.shared.isProxySetByOtherVariable.value) ||
            NetworkChangeNotifier.isCurrentSystemSetToClash(looser: true) ||
            NetworkChangeNotifier.hasInterfaceProxySetToClash()

        guard shouldCleanSystemProxy else { return nil }
        return ConfigManager.shared.isProxySetByOtherVariable.value
    }

    private static func prepareForTerminationWait() {
        if let statusItem = AppDelegate.shared.statusItem, statusItem.menu != nil {
            statusItem.menu = nil
        }
        AppDelegate.shared.disposeBag = DisposeBag()
    }

    private static func performProxyCleanup(forceDisable: Bool) async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                await SystemProxyManager.shared.disableProxy(forceDisable: forceDisable)
                return true
            }

            group.addTask {
                try? await Task.sleep(seconds: 5)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    @MainActor
    private static func replyShouldTerminate(app: NSApplication, initialDelay: TimeInterval) async {
        if initialDelay > 0 {
            try? await Task.sleep(seconds: initialDelay)
        }
        app.reply(toApplicationShouldTerminate: true)
        try? await Task.sleep(seconds: 1)
        app.reply(toApplicationShouldTerminate: true)
    }

    @MainActor
    private static func replyShouldCancelTermination(app: NSApplication) async {
        app.reply(toApplicationShouldTerminate: false)
    }

    @MainActor
    static func confirmAction() -> Bool {
        if NSApp.activationPolicy() == .regular {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Quit ClashX?", comment: "")
            alert.informativeText = NSLocalizedString("The active connections will be interrupted.", comment: "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
            return alert.runModal() == .alertFirstButtonReturn
        }
        return true
    }
}
