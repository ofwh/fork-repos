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

    func saveProxy() async {
        guard !Settings.disableRestoreProxy else { return }
        Logger.log("saveProxy", level: .debug)
        do {
            let payload = try await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.GetCurrentProxySetting())
            Logger.log("saveProxy done", level: .debug)
            savedProxyInfo = try payload.dictionary()
        } catch {
            Logger.log("saveProxy failed: \(error)", level: .error)
        }
    }

    func enableProxy() async {
        let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let socketPort = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        await enableProxy(port: port, socksPort: socketPort)
    }

    func enableProxy(port: Int, socksPort: Int) async {
        guard port > 0 && socksPort > 0 else {
            Logger.log("enableProxy fail: \(port) \(socksPort)", level: .error)
            return
        }
        if await SSIDSuspendTool.shared.shouldSuspend() {
            Logger.log("not enableProxy due to ssid in disabled list", level: .info)
            return
        }
        Logger.log("enableProxy", level: .debug)
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

    func disableProxy(forceDisable: Bool = false) async {
        let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let socketPort = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        await disableProxy(port: port, socksPort: socketPort, forceDisable: forceDisable)
    }
    
    func toggleTunMode(enabled: Bool, persistent: Bool = true) async {
        if enabled && persistent {
            if await SSIDSuspendTool.shared.shouldSuspend() {
                Logger.log("not enableTunProxy due to ssid in disabled list", level: .info)
                return
            }
        }
        await ConfigReloadManager.shared.setTunMode(enabled: enabled)
        if persistent {
            ConfigManager.shared.isTunModeEnabled = enabled
        }
    }

    func disableProxy(port: Int, socksPort: Int, forceDisable: Bool = false) async {
        Logger.log("disableProxy", level: .debug)

        if Settings.disableRestoreProxy || forceDisable {
            do {
                let message = ProxyConfigHelperMessages.DisableProxy(filterInterface: Settings.filterInterface)
                if let error = try await PrivilegedHelperManager.shared.request(message) {
                    Logger.log("disableProxy \(error)", level: .error)
                }
            } catch {
                Logger.log("disableProxy failed: \(error)", level: .error)
            }
            return
        }

        let savedProxyInfo = self.savedProxyInfo
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
    }

    func toggleSystemProxyEnabled() async {
        var shouldSaveProxy = true

        if ConfigManager.shared.isSystemProxyEnabled && ConfigManager.shared.isProxyPausedRelay.value {
            ConfigManager.shared.isSystemProxyEnabled = false
        } else if ConfigManager.shared.isProxySetByOtherRelay.value {
            ConfigManager.shared.isProxySetByOtherRelay.accept(false)
            ConfigManager.shared.isSystemProxyEnabled = true
            shouldSaveProxy = false
            await disableProxy(port: 0, socksPort: 0, forceDisable: true)
        } else {
            ConfigManager.shared.isSystemProxyEnabled.toggle()
        }

        if ConfigManager.shared.isSystemProxyEnabled {
            if shouldSaveProxy {
                await saveProxy()
            }
            await enableProxy()
        } else {
            await disableProxy()
        }
    }

    func updateProxyPortsIfNeeded(oldConfig: ClashConfig?, newConfig: ClashConfig) async {
        guard oldConfig?.usedHttpPort != newConfig.usedHttpPort ||
                oldConfig?.usedSocksPort != newConfig.usedSocksPort else { return }

        Logger.log("port config updated,new: \(newConfig.usedHttpPort),\(newConfig.usedSocksPort)")

        guard ConfigManager.shared.isSystemProxyEnabled else { return }
        await enableProxy(port: newConfig.usedHttpPort, socksPort: newConfig.usedSocksPort)
    }

    func resetProxySettingOnWakeupFromSleep() async {
        guard !ConfigManager.shared.isProxySetByOtherRelay.value,
              ConfigManager.shared.isSystemProxyEnabled else { return }
        guard NetworkChangeNotifier.getPrimaryInterface() != nil else { return }

        if !NetworkChangeNotifier.isCurrentSystemSetToClash() {
            let rawProxy = NetworkChangeNotifier.getRawProxySetting()
            Logger.log("Resting proxy setting, current:\(rawProxy)", level: .warning)
            await disableProxy()
            await enableProxy()
        }

        await MainActor.run {
            ConfigReloadManager.shared.resetStreamApiIfRemoteControlEnabled()
        }
    }
}
