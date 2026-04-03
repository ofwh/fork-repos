//
//  ConfigReloadManager.swift
//  ClashX
//

import Cocoa

@MainActor
final class ConfigReloadManager {
    static let shared = ConfigReloadManager()

    private var runAfterConfigReload = false

    private init() {}

    func prepareInitialAllowLanSync() {
        runAfterConfigReload = true
    }

    func syncConfig() async {
        guard let config = await ApiRequest.requestConfig() else { return }
        ConfigManager.shared.currentConfig = config
    }

    func syncConfigWithTun(_ isInit: Bool = false) async {
        await syncConfig()

        guard let config = ConfigManager.shared.currentConfig else { return }

        let enable = config.tun.enable

        if isInit, !enable {
            Logger.log("tun didn't set")
            return
        }

        try? await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.UpdateTun(state: enable, dns: ConfigManager.metaTunDNS))
        Logger.log("tun state updated, new: \(enable)")
    }

    func resetStreamApi() {
        ApiRequest.shared.delegate = AppDelegate.shared
        ApiRequest.shared.resetStreamApis()
    }

    func updateAllowLanSetting() async -> Bool {
        let allow = !ConfigManager.allowConnectFromLan
        await ApiRequest.updateAllowLan(allow: allow)
        await syncConfig()
        ConfigManager.allowConnectFromLan = allow
        return allow
    }

    func setTunMode(enabled: Bool) async {
        await ApiRequest.updateTun(enable: enabled)
        await syncConfigWithTun()
    }

    func setSniffing(enable: Bool) async {
        await ApiRequest.updateSniffing(enable: enable)
    }

    @discardableResult
    func updateConfig(configName: String? = nil, showNotification: Bool = true) async -> ErrorString? {
        await AppDelegate.shared.startProxyCore()
        guard ConfigManager.shared.isRunning else { return nil }

        let config = configName ?? ConfigManager.selectConfigName

        ClashProxy.cleanCache()

        let err = await ApiRequest.requestConfigUpdate(configName: config)
        if let err {
            UpdateConfigAction.showError(text: err, configName: config)
            return err
        }

        await syncConfigWithTun()
        resetStreamApi()
        await syncInitialAllowLanIfNeeded()

        if showNotification {
            UserNotificationCenter.shared.post(
                title: NSLocalizedString("Reload Config Succeed", comment: ""),
                info: NSLocalizedString("Success", comment: "")
            )
        }

        if let newConfigName = configName {
            ConfigManager.selectConfigName = newConfigName
        }

        await selectProxyGroupWithMemory()
        await selectOutBoundModeWithMenory()
        await MenuItemFactory.recreateProxyMenuItems()
        NotificationCenter.default.post(name: .reloadDashboard, object: nil)
        return nil
    }

    func handleClashConfigUpdated() async {
        if ConfigManager.shared.restoreSystemProxy {
            await SystemProxyManager.shared.enableProxy()
        }

        if ConfigManager.shared.restoreTunProxy {
            await ApiRequest.updateTun(enable: true)
            try? await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.UpdateTun(state: true, dns: ConfigManager.metaTunDNS))
        } else {
            await syncConfigWithTun(true)
        }

        SSIDSuspendTool.shared.setup()

        resetStreamApi()
        await syncInitialAllowLanIfNeeded()
        await selectProxyGroupWithMemory()
        await MenuItemFactory.recreateProxyMenuItems()
        NotificationCenter.default.post(name: .reloadDashboard, object: nil)
    }

    func selectOutBoundModeWithMenory() async {
        _ = await ApiRequest.updateOutBoundMode(mode: ConfigManager.selectOutBoundMode)
        await ConnectionManager.closeAllConnection()
        await syncConfig()
    }

    private func selectAllowLanWithMenory() async {
        await ApiRequest.updateAllowLan(allow: ConfigManager.allowConnectFromLan)
        await syncConfig()
    }

    private func syncInitialAllowLanIfNeeded() async {
        guard runAfterConfigReload else { return }
        runAfterConfigReload = false
        await selectAllowLanWithMenory()
    }

    private func selectProxyGroupWithMemory() async {
        let items = [SavedProxyModel](ConfigManager.selectedProxyRecords).filter {
            $0.config == ConfigManager.selectConfigName
        }
        let failedKeys = await withTaskGroup(of: String?.self, returning: [String].self) { group in
            items.forEach { item in
                Logger.log("Auto selecting \(item.group) \(item.selected)", level: .debug)
                let groupName = item.group
                let selected = item.selected
                let itemKey = item.key

                group.addTask {
                    let success = await ApiRequest.updateProxyGroup(group: groupName, selectProxy: selected)
                    return success ? nil : itemKey
                }
            }

            var failedKeys: [String] = []
            for await failedKey in group {
                guard let failedKey else { continue }
                failedKeys.append(failedKey)
            }
            return failedKeys
        }

        guard !failedKeys.isEmpty else { return }
        ConfigManager.selectedProxyRecords.removeAll { model in
            failedKeys.contains(model.key)
        }
    }
}