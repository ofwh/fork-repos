//
//  SystemProxyManager.swift
//  ClashX
//
//  Created by yichengchen on 2019/8/17.
//  Copyright © 2019 west2online. All rights reserved.
//

import AppKit
import ServiceManagement

class SystemProxyManager: NSObject {
    static let shared = SystemProxyManager()

    private var savedProxyInfo: [String: Any] {
        get {
            return UserDefaults.standard.dictionary(forKey: "kSavedProxyInfo") ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kSavedProxyInfo")
        }
    }

    func saveProxy() {
        guard !Settings.disableRestoreProxy else { return }
        Logger.log("saveProxy", level: .debug)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let payload = try await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.GetCurrentProxySetting())
                Logger.log("saveProxy done", level: .debug)
                self.savedProxyInfo = try payload.dictionary()
            } catch {
                Logger.log("saveProxy failed: \(error)", level: .error)
            }
        }
    }

    func enableProxy() {
        let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let socketPort = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        enableProxy(port: port, socksPort: socketPort)
    }

    func enableProxy(port: Int, socksPort: Int) {
        guard port > 0 && socksPort > 0 else {
            Logger.log("enableProxy fail: \(port) \(socksPort)", level: .error)
            return
        }
        if SSIDSuspendTool.shared.shouldSuspend() {
            Logger.log("not enableProxy due to ssid in disabled list", level: .info)
            return
        }
        Logger.log("enableProxy", level: .debug)
        Task {
            do {
                let message = ProxyConfigHelperMessages.EnableProxy(port: port,
                                                                    socksPort: socksPort,
                                                                    pac: nil,
                                                                    filterInterface: Settings.filterInterface,
                                                                    ignoreList: Settings.proxyIgnoreList)
                if let error = try await PrivilegedHelperManager.shared.request(message) {
                    Logger.log("enableProxy \(error)", level: .error)
                }
            } catch {
                Logger.log("enableProxy failed: \(error)", level: .error)
            }
        }
    }

    func disableProxy(forceDisable: Bool = false, complete: (() -> Void)? = nil) {
        let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let socketPort = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        SystemProxyManager.shared.disableProxy(port: port, socksPort: socketPort, forceDisable: forceDisable, complete: complete)
    }

    func disableProxy(port: Int, socksPort: Int, forceDisable: Bool = false, complete: (() -> Void)? = nil) {
        Logger.log("disableProxy", level: .debug)

        if Settings.disableRestoreProxy || forceDisable {
            Task { @MainActor in
                do {
                    let message = ProxyConfigHelperMessages.DisableProxy(filterInterface: Settings.filterInterface)
                    if let error = try await PrivilegedHelperManager.shared.request(message) {
                        Logger.log("disableProxy \(error)", level: .error)
                    }
                } catch {
                    Logger.log("disableProxy failed: \(error)", level: .error)
                }
                complete?()
            }
            return
        }

        let savedProxyInfo = self.savedProxyInfo
        Task { @MainActor in
            do {
                let info = try ProxyConfigHelperPropertyList(savedProxyInfo)
                let message = ProxyConfigHelperMessages.RestoreProxy(currentPort: port,
                                                                    socksPort: socksPort,
                                                                    info: info,
                                                                    filterInterface: Settings.filterInterface)
                if let error = try await PrivilegedHelperManager.shared.request(message) {
                    Logger.log("restoreProxy \(error)", level: .error)
                }
            } catch {
                Logger.log("restoreProxy failed: \(error)", level: .error)
            }
            complete?()
        }
    }
}
