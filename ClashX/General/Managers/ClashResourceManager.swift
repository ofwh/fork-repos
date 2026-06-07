import AppKit
import CryptoKit
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

    private static let ruleMD5Key = "meta-rules-md5"

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
        let destPath = "\(kConfigFolderPath)\(file.rawValue)"
        let storedMD5 = storedRuleMD5Map()[file.rawValue]

        if fileManage.fileExists(atPath: destPath) {
            let versionChange = AppVersionUtil.hasVersionChanged || AppVersionUtil.isFirstLaunch
            if versionChange {
                if let currentMD5 = fileMD5(atPath: destPath), currentMD5 == storedMD5 {
                    try? fileManage.removeItem(atPath: destPath)
                }
            }
        }

        if !fileManage.fileExists(atPath: destPath) {
            if let gzUrl = Bundle.main.url(forResource: file.rawValue, withExtension: "gz", subdirectory: "meta-rules-dat") {
                do {
                    let data = try Data(contentsOf: gzUrl).gunzipped()
                    try data.write(to: URL(fileURLWithPath: destPath))
                    saveRuleMD5(file.rawValue, md5: md5Hex(of: data))
                } catch let err {
                    Logger.log("add \(file.rawValue) fail:\(err)", level: .error)
                }
            } else {
                Logger.log("missing bundled rule file: \(file.rawValue)", level: .error)
            }
        }
    }

    private static func storedRuleMD5Map() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: ruleMD5Key) as? [String: String] ?? [:]
    }

    private static func saveRuleMD5(_ name: String, md5: String) {
        var map = storedRuleMD5Map()
        map[name] = md5
        UserDefaults.standard.set(map, forKey: ruleMD5Key)
    }

    private static func md5Hex(of data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileMD5(atPath path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return md5Hex(of: data)
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
