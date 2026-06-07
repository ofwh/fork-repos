import AppKit
import Foundation
import AsyncHTTPClient
import Gzip

class ClashResourceManager {
    static let shared = ClashResourceManager()

    enum RuleFiles: String {
        case mmdb = "country.mmdb"
        case geosite = "geosite.dat"
        case geoip = "geoip.dat"
        case bundleMRS = "BundleMRS.7z"
    }

    @MainActor
    private var updateGeoTask: Task<Void, Never>?

    private init() {}

    static func check() -> Bool {
        checkConfigDir()
        checkRuleFiles()
        return true
    }

    static func checkConfigDir() {
        var isDir: ObjCBool = true

        if !FileManager.default.fileExists(atPath: kConfigFolderPath, isDirectory: &isDir) {
            do {
                try FileManager.default.createDirectory(atPath: kConfigFolderPath, withIntermediateDirectories: true, attributes: nil)
            } catch let err {
                Logger.log("\(err.localizedDescription) \(kConfigFolderPath)")
                showCreateConfigDirFailAlert(err: err.localizedDescription)
            }
        }
    }

    static func checkRuleFiles() {
        checkRule(.mmdb)
        checkRule(.geoip)
        checkRule(.geosite)
        checkRule(.bundleMRS)
    }

    static func checkRule(_ file: RuleFiles) {
        let fileManage = FileManager.default
        let destPath = kConfigFolderPath + "meta-rules-dat" + file.rawValue

        // Remove old mmdb file after version update.
        if fileManage.fileExists(atPath: destPath) {
            let versionChange = AppVersionUtil.hasVersionChanged || AppVersionUtil.isFirstLaunch
            if versionChange {
                try? fileManage.removeItem(atPath: destPath)
            }
        }

        if !fileManage.fileExists(atPath: destPath) {
            if let gzUrl = Bundle.main.url(forResource: file.rawValue, withExtension: "gz") {
                do {
                    let data = try Data(contentsOf: gzUrl).gunzipped()
                    try data.write(to: URL(fileURLWithPath: destPath))
                } catch let err {
                    Logger.log("add \(file.rawValue) fail:\(err)", level: .error)
                }
            }
        }
    }

    static func showCreateConfigDirFailAlert(err: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("ClashX fail to create ~/.config/clash.meta folder. Please check privileges or manually create folder and restart ClashX." + err, comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}

extension ClashResourceManager {
    @MainActor
    func updateGeoDatabases() async {
        guard updateGeoTask == nil else { return }

        _ = await ApiRequest.updateGEO()
        UserNotificationCenter.shared.post(title: NSLocalizedString("Updating GEO Databases...", comment: ""), info: NSLocalizedString("Good luck to you  🙃", comment: ""))

        updateGeoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.updateGeoTask = nil
            }

            while !Task.isCancelled {
                if await self.pollGeoUpdate() {
                    return
                }
                try? await Task.sleep(seconds: 0.5)
            }
        }
    }

    @MainActor
    private func pollGeoUpdate() async -> Bool {
        let rules = await ApiRequest.getRules()
        guard updateGeoTask != nil else { return true }

        if let rule = rules.first,
           rule.payload == ClashMetaConfig.initRulePayload {
            Logger.log("Update GEO Finished.")
            await ConfigReloadManager.shared.updateConfig(showNotification: false)
            UserNotificationCenter.shared.post(title: "Update GEO Databases Finished.", info: "")

            return true
        } else {
            return false
        }
    }

    static func updateGeoIP() {
        guard let url = showCustomAlert() else { return }
        
        try? HTTPClient.shared.execute(
            request: .init(url: url),
            delegate: FileDownloadDelegate(path: kConfigFolderPath.appending("/Country.mmdb"))
        )
        .futureResult
        .whenComplete {
            var info: String
            switch $0 {
            case .success:
                info = NSLocalizedString("Success!", comment: "")
                Logger.log("update success")
            case .failure(let err):
                info = NSLocalizedString("Fail:", comment: "") + err.localizedDescription
                Logger.log("update fail \(err)")
            }
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Update GEOIP Database", comment: "")
            alert.informativeText = info
            alert.runModal()
        }
    }

    private static func showCustomAlert() -> String? {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Custom your GEOIP MMDB download address.", comment: "")
        let inputView = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        inputView.placeholderString = Settings.defaultMmdbDownloadUrl
        if Settings.mmdbDownloadUrl.isEmpty {
            inputView.stringValue = Settings.defaultMmdbDownloadUrl
        } else {
            inputView.stringValue = Settings.mmdbDownloadUrl
        }
        alert.accessoryView = inputView
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            if inputView.stringValue.isEmpty {
                return inputView.placeholderString
            }
            Settings.mmdbDownloadUrl = inputView.stringValue
            return inputView.stringValue
        }
        return nil
    }
}
