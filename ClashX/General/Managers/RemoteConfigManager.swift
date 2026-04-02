//
//  RemoteConfigManager.swift
//  ClashX
//
//  Created by yicheng on 2018/11/6.
//  Copyright © 2018 west2online. All rights reserved.
//

import Alamofire
import Cocoa

class RemoteConfigManager {
    var configs: [RemoteConfigModel] = []
    var refreshActivity: NSBackgroundActivityScheduler?

    static let shared = RemoteConfigManager()

    private init() {
        if let savedConfigs = UserDefaults.standard.object(forKey: "kRemoteConfigs") as? Data {
            let decoder = JSONDecoder()
            if let loadedConfig = try? decoder.decode([RemoteConfigModel].self, from: savedConfigs) {
                configs = loadedConfig
            } else {
                assertionFailure()
            }
        }
        migrateOldRemoteConfig()
        setupAutoUpdateTimer()
    }

    func saveConfigs() {
        Logger.log("Saving Remote Config Setting")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(configs) {
            UserDefaults.standard.set(encoded, forKey: "kRemoteConfigs")
        }
    }

    func migrateOldRemoteConfig() {
        if let url = UserDefaults.standard.string(forKey: "kRemoteConfigUrl"),
           let name = URL(string: url)?.host {
            configs.append(RemoteConfigModel(url: url, name: name))
            UserDefaults.standard.removeObject(forKey: "kRemoteConfigUrl")
            saveConfigs()
        }
    }

    func setupAutoUpdateTimer() {
        refreshActivity?.invalidate()
        refreshActivity = nil
        guard RemoteConfigManager.autoUpdateEnable else {
            Logger.log("autoUpdateEnable did not enable,autoUpateTimer invalidated.")
            return
        }
        Logger.log("set up autoUpateTimer")

        refreshActivity = NSBackgroundActivityScheduler(identifier: "com.ClashX.configupdate")
        refreshActivity?.repeats = true
        refreshActivity?.interval = 60 * 60 * 2 // Two hour
        refreshActivity?.tolerance = 60 * 60

        refreshActivity?.schedule { [weak self] completionHandler in
            self?.autoUpdateCheck()
            completionHandler(NSBackgroundActivityScheduler.Result.finished)
        }
    }

    static var autoUpdateEnable: Bool {
        get {
            return UserDefaults.standard.object(forKey: "kAutoUpdateEnable") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kAutoUpdateEnable")
            RemoteConfigManager.shared.setupAutoUpdateTimer()
        }
    }

    @objc func autoUpdateCheck() {
        guard RemoteConfigManager.autoUpdateEnable else { return }
        Logger.log("Tigger config auto update check")
        updateCheck()
    }

    func updateCheck(ignoreTimeLimit: Bool = false, showNotification: Bool = false) {
        let currentConfigName = ConfigManager.selectConfigName

        let group = DispatchGroup()

        for config in configs {
            if config.updating { continue }
            let timeLimitNoMantians = Date().timeIntervalSince(config.updateTime ?? Date(timeIntervalSince1970: 0)) < Settings.configAutoUpdateInterval

            if timeLimitNoMantians && !ignoreTimeLimit {
                Logger.log("[Auto Upgrade] Bypassing \(config.name) due to time check")
                continue
            }
            Logger.log("[Auto Upgrade] Requesting \(config.name)")
            let isCurrentConfig = config.name == currentConfigName
            config.updating = true
            group.enter()
            Task { @MainActor [weak config] in
                guard let config = config else { return }
                let error = await RemoteConfigManager.updateConfig(config: config)

                config.updating = false
                group.leave()
                if error == nil {
                    config.updateTime = Date()
                }

                if isCurrentConfig {
                    if let error = error {
                        if showNotification {
                            UserNotificationCenter.shared.post(title: NSLocalizedString("Remote Config Update Fail", comment: ""),
                                      info: "\(config.name): \(error)")
                        }

                    } else {
                        if showNotification {
                            let info = "\(config.name): \(NSLocalizedString("Succeed!", comment: ""))"
                            UserNotificationCenter.shared.post(title: NSLocalizedString("Remote Config Update", comment: ""), info: info)
                        }
                        _ = await AppDelegate.shared.updateConfig(showNotification: false)
                    }
                }
                Logger.log("[Auto Upgrade] Finish \(config.name) result: \(error ?? "succeed")")
            }
        }

        group.notify(queue: .main) {
            [weak self] in
            self?.saveConfigs()
        }
    }

    static func getRemoteConfigData(config: RemoteConfigModel) async -> (String?, String?) {
        guard var urlRequest = try? URLRequest(url: config.url, method: .get) else {
            assertionFailure()
            Logger.log("[getRemoteConfigData] url incorrect,\(config.name) \(config.url)")
            return (nil, nil)
        }
        urlRequest.cachePolicy = .reloadIgnoringCacheData

        return await withCheckedContinuation { continuation in
            AF.request(urlRequest)
                .validate()
                .responseString(encoding: .utf8) { res in
                    continuation.resume(returning: (try? res.result.get(), res.response?.suggestedFilename))
                }
        }
    }

    static func updateConfig(config: RemoteConfigModel) async -> String? {
        let (configString, suggestedFilename) = await getRemoteConfigData(config: config)
        guard let newConfig = configString else {
            return NSLocalizedString("Download fail", comment: "")
        }

        let verifyRes = verifyConfig(string: newConfig)
        if let error = verifyRes {
            return NSLocalizedString("Remote Config Format Error", comment: "") + ": " + error
        }

        if let suggestName = suggestedFilename, config.isPlaceHolderName {
            let name = URL(fileURLWithPath: suggestName).deletingPathExtension().lastPathComponent
            if !shared.configs.contains(where: { $0.name == name }) {
                config.name = name
            }
        }
        config.isPlaceHolderName = false

        if ICloudManager.shared.useiCloud.value {
            ConfigFileManager.shared.stopWatchConfigFile()
        }
        if config.name == ConfigManager.selectConfigName {
            ConfigFileManager.shared.pauseForNextChange()
        }

        let savePath: String?
        if ICloudManager.shared.useiCloud.value {
            savePath = await withCheckedContinuation { continuation in
                ICloudManager.shared.getUrl { url in
                    let saveUrl = url?.appendingPathComponent(Paths.configFileName(for: config.name))
                    continuation.resume(returning: saveUrl?.path)
                }
            }
        } else {
            savePath = Paths.localConfigPath(for: config.name)
        }

        guard let savePath else { return NSLocalizedString("Download fail", comment: "") }

        do {
            if FileManager.default.fileExists(atPath: savePath) {
                try FileManager.default.removeItem(atPath: savePath)
            }
            try newConfig.write(to: URL(fileURLWithPath: savePath), atomically: true, encoding: .utf8)
            return nil
        } catch let err {
            return err.localizedDescription
        }
    }

    static func createCacheConfig(string: String) -> String? {
		let path = Paths.tempPath() + "/cacheConfigs"
        let confPath = path + "/\(UUID().uuidString).yaml"

        let fm = FileManager.default
        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)

        if fm.fileExists(atPath: confPath) {
            try? fm.removeItem(atPath: confPath)
        }

        guard fm.createFile(atPath: confPath, contents: string.data(using: .utf8)) else {
            return nil
        }
        return confPath
    }

    static func verifyConfig(string: String) -> ErrorString? {
        guard let confPath = createCacheConfig(string: string) else {
            return "Create verify config file failed"
        }
		
        return ClashProcess.verify(kConfigFolderPath, confFilePath: confPath)
    }

    static func showAdd() {
        let alertView = NSAlert()
        alertView.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alertView.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alertView.messageText = NSLocalizedString("Update remote config update interval", comment: "")
        let setupView = RemoteConfigUpdateIntervalSettingView()
        setupView.frame = NSRect(x: 0, y: 0, width: 100, height: 22)
        alertView.accessoryView = setupView
        let response = alertView.runModal()

        guard response == .alertFirstButtonReturn else { return }
        let stringValue = setupView.textfield.stringValue
        guard let intValue = Int(stringValue), intValue > 0 else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.informativeText = NSLocalizedString("Should be a least 1 hour", comment: "")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.runModal()
            return
        }
        Settings.configAutoUpdateInterval = TimeInterval(intValue * 60 * 60)
        RemoteConfigManager.shared.autoUpdateCheck()
    }
}
