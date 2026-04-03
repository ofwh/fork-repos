//
//  AppVersionUtil.swift
//  ClashX
//
//  Created by CYC on 2019/2/18.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

class AppVersionUtil: NSObject {
    private static let shared = AppVersionUtil()

    private static let kLastVersionNumberKey = "com.clashX.lastVersionNumber"
    private static let kConfigFolderMigrationTipKey = "ClashX_Meta_1.3.0_UpdateTips"
    private static let configFolderMigrationTipInfo = "Config Floder migrated from\n~/.config/clash to\n~/.config/clash.meta"
    private static let configFolderMigrationVersion = "1.3.0"
    private static var hasHandledPostLaunchUpdateTips = false

    private let lastVersionNumber: String?

    static var currentVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static var currentBuild: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static var isBeta: Bool {
        return Bundle.main.object(forInfoDictionaryKey: "BETA") as? Bool ?? false
    }

    override init() {
        lastVersionNumber = UserDefaults.standard.string(forKey: AppVersionUtil.kLastVersionNumberKey)
        UserDefaults.standard.set(AppVersionUtil.currentVersion, forKey: AppVersionUtil.kLastVersionNumberKey)
    }

    static var isFirstLaunch: Bool {
        return shared.lastVersionNumber == nil
    }

    static var hasVersionChanged: Bool {
        return shared.lastVersionNumber != currentVersion
    }
}

extension AppVersionUtil {
    @MainActor
    static func showUpgradeAlert() async {
        guard !hasHandledPostLaunchUpdateTips,
              let lastVersion = shared.lastVersionNumber,
              hasVersionChanged else { return }

        hasHandledPostLaunchUpdateTips = true
        await WebCacheCleaner.clean()

        guard lastVersion.compare(configFolderMigrationVersion, options: .numeric) == .orderedAscending,
              !UserDefaults.standard.bool(forKey: kConfigFolderMigrationTipKey) else { return }

        UserDefaults.standard.set(true, forKey: kConfigFolderMigrationTipKey)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Update Tips", comment: "")
        alert.informativeText = configFolderMigrationTipInfo
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }
}
