//
//  ICloudManager.swift
//  ClashX
//
//  Created by yicheng on 2020/5/10.
//  Copyright © 2020 west2online. All rights reserved.
//

import Cocoa
import RxCocoa
import RxSwift

private actor ICloudFileSystem {
    func getDocumentsURL() -> URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }

        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
            return documentsURL
        } catch {
            Logger.log("\(error)")
            return nil
        }
    }

    func getConfigFilesList() -> [String] {
        guard let documentsURL = getDocumentsURL(),
              let fileURLs = try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path) else {
            return []
        }

        return fileURLs
            .filter { String($0.split(separator: ".").last ?? "") == "yaml" }
            .map { $0.split(separator: ".").dropLast().joined(separator: ".") }
    }

    func ensureDefaultConfigIfNeeded(sampleConfigPath: String, defaultConfigPath: String) -> Bool {
        guard let documentsURL = getDocumentsURL() else {
            return false
        }

        let files = try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path)
        guard files?.isEmpty == true else {
            return true
        }

        try? FileManager.default.copyItem(atPath: sampleConfigPath, toPath: defaultConfigPath)
        try? FileManager.default.copyItem(atPath: sampleConfigPath, toPath: documentsURL.appendingPathComponent("config.yaml").path)
        return true
    }
}

class ICloudManager {
    static let shared = ICloudManager()
    private var metaQuery: NSMetadataQuery?
    private var enableMenuItem: NSMenuItem?
    private let fileSystem = ICloudFileSystem()
    private(set) var icloudAvailable = false {
        didSet { useICloudRelay.accept(userEnableiCloud && icloudAvailable) }
    }

    private var disposeBag = DisposeBag()

    let useICloudRelay = BehaviorRelay<Bool>(value: false)

    var userEnableiCloud: Bool = UserDefaults.standard.bool(forKey: "kUserEnableiCloud") {
        didSet {
            UserDefaults.standard.set(userEnableiCloud, forKey: "kUserEnableiCloud")
            useICloudRelay.accept(userEnableiCloud && icloudAvailable)
        }
    }

    func setup() {
        addNotification()
        useICloudRelay.distinctUntilChanged().filter { $0 }.subscribe {
            [weak self] _ in
            Task { @MainActor in
                await self?.checkiCloud()
            }
        }.disposed(by: disposeBag)

        icloudAvailable = isICloudAvailable()
        useICloudRelay.accept(userEnableiCloud && icloudAvailable)
    }

    func getConfigFilesList() async -> [String] {
        await fileSystem.getConfigFilesList()
    }

    @MainActor
    private func checkiCloud() async {
        guard let sampleConfigPath = Bundle.main.path(forResource: "sampleConfig", ofType: "yaml") else {
            return
        }

        guard await fileSystem.ensureDefaultConfigIfNeeded(sampleConfigPath: sampleConfigPath, defaultConfigPath: kDefaultConfigFilePath) else {
            self.icloudAvailable = false
            return
        }
    }

    private func isICloudAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    func getUrl() async -> URL? {
        await fileSystem.getDocumentsURL()
    }

    private func addNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(iCloudAccountAvailabilityChanged), name: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil)
    }

    @objc func iCloudAccountAvailabilityChanged() {
        icloudAvailable = isICloudAvailable()
    }
}
