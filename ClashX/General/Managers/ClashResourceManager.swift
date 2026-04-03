import Alamofire
import AppKit
import Foundation
import Gzip

class ClashResourceManager {
    static let shared = ClashResourceManager()

    enum RuleFiles: String {
        case mmdb = "country.mmdb"
        case geosite = "geosite.dat"
        case geoip = "geoip.dat"
    }

    private var updateGeoTimer: Timer?

    private init() {}

    static func check() -> Bool {
        checkConfigDir()
        checkMMDB()
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

    static func checkMMDB() {
        checkRule(.mmdb)
        checkRule(.geoip)
        checkRule(.geosite)
    }

    static func checkRule(_ file: RuleFiles) {
        let fileManage = FileManager.default
        let destPath = kConfigFolderPath + file.rawValue

        // Remove old mmdb file after version update.
        if fileManage.fileExists(atPath: destPath) {
            let versionChange = AppVersionUtil.hasVersionChanged || AppVersionUtil.isFirstLaunch
//            switch file {
//            case .mmdb:
//                let vaild = verifyGEOIPDataBase().toBool()
//                let customMMDBSet = !Settings.mmdbDownloadUrl.isEmpty
//                if !vaild || (versionChange && customMMDBSet) {
//                    try? fileManage.removeItem(atPath: destPath)
//                }
//            case .geosite, .geoip:
                if versionChange {
                    try? fileManage.removeItem(atPath: destPath)
                }
//            }
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
        guard updateGeoTimer == nil else { return }

        updateGeoTimer = Timer.scheduledTimer(withTimeInterval: 500, repeats: true) { [weak self] timer in
            timer.fireDate = .init(timeIntervalSinceNow: 5)

            Task { [weak self] in
                await self?.pollGeoUpdate(with: timer)
            }
        }

        _ = await ApiRequest.updateGEO()
        UserNotificationCenter.shared.post(title: NSLocalizedString("Updating GEO Databases...", comment: ""), info: NSLocalizedString("Good luck to you  🙃", comment: ""))
        updateGeoTimer?.fire()
    }

    @MainActor
    private func pollGeoUpdate(with timer: Timer) async {
        let rules = await ApiRequest.getRules()
        guard updateGeoTimer != nil else { return }

        if let rule = rules.first,
           rule.payload == ClashMetaConfig.initRulePayload {
            Logger.log("Update GEO Finished.")
            await ConfigReloadManager.shared.updateConfig(showNotification: false)
            UserNotificationCenter.shared.post(title: "Update GEO Databases Finished.", info: "")

            timer.invalidate()
            updateGeoTimer = nil
        } else {
            timer.fireDate = .init(timeIntervalSinceNow: 0.5)
        }
    }

    static func updateGeoIP() {
        guard let url = showCustomAlert() else { return }
        AF.download(url, to: { _, _ in
            let path = kConfigFolderPath.appending("/Country.mmdb")
            return (URL(fileURLWithPath: path), .removePreviousFile)
        }).response { res in
            var info: String
            switch res.result {
            case .success:
                info = NSLocalizedString("Success!", comment: "")
                Logger.log("update success")
            case let .failure(err):
                info = NSLocalizedString("Fail:", comment: "") + err.localizedDescription
                Logger.log("update fail \(err)")
            }
//            if !verifyGEOIPDataBase().toBool() {
//                info = "Database verify fail"
//                checkMMDB()
//            }
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
