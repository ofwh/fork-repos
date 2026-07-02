//
//  ConfigFileManager.swift
//  ClashX
//
//  Created by CYC on 2018/8/5.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import AppKit
import Foundation
import SwiftyJSON

@MainActor
class ConfigFileManager {
    static let shared = ConfigFileManager()
    private var watchTask: Task<Void, Never>?
    private var pause = false

    func pauseForNextChange() {
        pause = true
    }

    func watchFile(path: String) {
        stopWatchConfigFile()
        
        watchTask = Task {
            for await event in FileWatcher.events(for: path) {
                guard !Task.isCancelled else { break }
                guard !self.pause else {
                    self.pause = false
                    continue
                }
                if event.flags.contains(.itemModified) || event.flags.contains(.itemRenamed) {
                    UserNotificationCenter.shared.postConfigFileChangeDetectionNotice()
                    NotificationCenter.default.post(Notification(name: .configFileChange))
                }
            }
        }
    }

    func stopWatchConfigFile() {
        watchTask?.cancel()
        watchTask = nil
        pause = false
    }

    @discardableResult
    static func backupAndRemoveConfigFile() -> Bool {
        let path = kDefaultConfigFilePath
        if FileManager.default.fileExists(atPath: path) {
            let newPath = "\(kConfigFolderPath)config_\(Date().timeIntervalSince1970).yaml"
            try? FileManager.default.moveItem(atPath: path, toPath: newPath)
        }
        return true
    }

    static func copySampleConfigIfNeed() {
        if !FileManager.default.fileExists(atPath: kDefaultConfigFilePath) {
            let path = Bundle.main.path(forResource: "sampleConfig", ofType: "yaml")!
            try? FileManager.default.copyItem(atPath: path, toPath: kDefaultConfigFilePath)
        }
    }

    func openConfigFolder() async {
        if ICloudManager.shared.useICloudRelay.value {
            guard let url = await ICloudManager.shared.getUrl() else { return }
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.openFilePath(kConfigFolderPath)
        }
    }
}
