//
//  SSIDSuspendTool.swift
//  ClashX Pro
//
//  Created by yicheng on 2023/5/24.
//  Copyright © 2023 west2online. All rights reserved.
//

import CoreLocation
import CoreWLAN
import Foundation
import RxCocoa
import RxSwift
import AppKit

@MainActor
class SSIDSuspendTool: NSObject {
    static let shared = SSIDSuspendTool()
    private var ssidChangePublisher = PublishSubject<String>()
    private var disposeBag = DisposeBag()
    private lazy var locationManager = CLLocationManager()

    var showNoticeOnNotPermission = false
    private(set) var isOverrideActive = false

    /// True iff the location authorization state is final (granted, denied, or restricted).
    /// `.notDetermined` returns false — used to defer enabling TUN until it's resolved,
    /// avoiding a brief DNS-hijack window during SSID-suspend startup.
    var isLocationPermissionResolved: Bool {
        locationManager.authorizationStatus != .notDetermined
    }

    func setOverride(_ active: Bool) async {
        isOverrideActive = active
        await update()
    }

    func checkAndHandleOverride(isTun: Bool, requestedEnable: Bool) async -> Bool {
        let isBlacklisted = await isCurrentSSIDInBlacklist()
        if isBlacklisted && !isOverrideActive {
            if showSSIDOverrideAlert() {
                await setOverride(true)
            } else {
                return false
            }
        }

        let isAlreadyEnabled = isTun
            ? ProxyManager.shared.runtimeState.tunActive
            : ProxyManager.shared.runtimeState.systemProxyActive
        if requestedEnable && isAlreadyEnabled {
            return false
        }

        return true
    }

    private func showSSIDOverrideAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Current SSID is in the auto-suspend list.", comment: "")
        alert.informativeText = NSLocalizedString("Do you want to enable the proxy anyway? This override will be cleared when you switch WiFi or restart ClashX.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Enable Anyway", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func setup() async {
        if AppVersionUtil.hasVersionChanged {
            showNoticeOnNotPermission = true
        }
        await requestPermissionIfNeed()
        do {
            try CWWiFiClient.shared().startMonitoringEvent(with: .ssidDidChange)
            CWWiFiClient.shared().delegate = self
            ssidChangePublisher
                .observe(on: MainScheduler.instance)
                .debounce(.seconds(1), scheduler: MainScheduler.instance)
                .delay(.seconds(1), scheduler: MainScheduler.instance)
                .bind { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.update()
                    }
                }.disposed(by: disposeBag)
        } catch let err {
            Logger.log(String(describing: err), level: .warning)
            NotificationCenter
                .default
                .rx
                .notification(.systemNetworkStatusDidChange)
                .observe(on: MainScheduler.instance)
                .delay(.seconds(2), scheduler: MainScheduler.instance)
                .bind { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.update()
                    }
                }.disposed(by: disposeBag)
        }
        ProxyManager.shared
            .stateDidChange
            .asObservable()
            .map { $0.suspend.isSuspended }
            .distinctUntilChanged()
            .bind { pause in
                Task {
                    await self.handleProxySuspend(pause: pause)
                }
            }.disposed(by: disposeBag)

        await update()

        // Permission may already be in a final state (.authorized/.denied) in which
        // case locationManagerDidChangeAuthorization never fires. Re-reconcile here
        // so enableTun's isLocationPermissionResolved guard can now pass.
        if isLocationPermissionResolved {
            await ProxyManager.shared.reconcileState()
        }
    }

    func requestPermissionIfNeed() async {
        defer {
            showNoticeOnNotPermission = false
        }

        if Settings.disableSSIDList.isEmpty { return }
        if locationManager.authorizationStatus == .notDetermined {
            Logger.log("request location permission")
            locationManager.desiredAccuracy = kCLLocationAccuracyReduced
            locationManager.delegate = self
            locationManager.requestAlwaysAuthorization()
        } else if locationManager.authorizationStatus != .authorized {
            if showNoticeOnNotPermission {
                try? await Task.sleep(seconds: 0.1)
                self.openLocationSettings()
            }
        }
        
    }

    func update() async {
        Logger.log("Update suspend state")
        await ProxyManager.shared.setSuspended(await shouldSuspend())
    }

    func handleProxySuspend(pause: Bool) async {
        await ProxyManager.shared.setSuspended(pause)
    }

    func shouldSuspend() async -> Bool {
        if isOverrideActive { return false }
        return await isCurrentSSIDInBlacklist()
    }

    func isCurrentSSIDInBlacklist() async -> Bool {
        guard let currentSSID = await getCurrentSSID() else {
            return false
        }
        return Settings.disableSSIDList.contains(currentSSID)
    }

    private func getCurrentSSID() async -> String? {
        guard locationManager.authorizationStatus != .authorized else {
            return CWWiFiClient.shared().interface()?.ssid()
        }
        
        if #available(macOS 14.4, *) {
            // sudo wdutil info
            // SSID : <redacted>
            return nil
        } else {
            let info = await Command(cmd: "/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport", args: ["-I"]).run()
            let ssid = info.components(separatedBy: "\n")
                .lazy
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { $0.starts(with: "SSID:") }?
                .components(separatedBy: ":")
                .last?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ssid
        }
        
    }

    private func openLocationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Location")!)
        NSApp.activate(ignoringOtherApps: true)
        NSAlert.alert(with: NSLocalizedString("Please enable the location service for ClashX to detect your current WiFi network's SSID name and provide the auto-suspend services.", comment: ""))
    }
}

extension SSIDSuspendTool: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Logger.log("Location status: \(status.rawValue)")
        guard status != .notDetermined else { return }
        Task {
            await self.update()
            // Permission now resolved; re-apply TUN intent that may have been deferred
            // during startup (when isLocationPermissionResolved was still false).
            await ProxyManager.shared.reconcileState()
            if status != .authorized && self.showNoticeOnNotPermission {
                self.openLocationSettings()
            }
            self.showNoticeOnNotPermission = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension SSIDSuspendTool: @preconcurrency CWEventDelegate {
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        isOverrideActive = false
        ssidChangePublisher.onNext(interfaceName)
    }
}
