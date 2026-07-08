//
//  ExitManager.swift
//  ClashX
//
//  Copyright © 2024 west2online. All rights reserved.
//

import AppKit
import Atomics
import Foundation
import RxSwift


@MainActor
final class ExitManager {
    static let shared = ExitManager()

    private let normalTimeout: TimeInterval = 5
    private let forceTimeout: TimeInterval = 2

    private(set) var isTerminating = false
    private var forceQuitPending = false

    // MARK: - External API

    func requestQuit(force: Bool) {
        forceQuitPending = force
        #warning("Use thread 'global' to ensure 'Task' in 'applicationShouldTerminate' executes correctly. 💩💩💩")
        DispatchQueue.global(qos: .userInitiated).async {
            NSApp.terminate(nil)
        }
    }
    
    func handleShouldTerminate() async -> Bool {
        guard !isTerminating else {
            return true
        }
        isTerminating = true

        let shouldForce = forceQuitPending
        forceQuitPending = false

        if !shouldForce {
            guard confirmAction() else {
                isTerminating = false
                return false
            }
        }

        ApiRequest.shared.prepareForTermination()

        // Compute cleanup decision BEFORE launching stopTask.
        // Reading runtimeState.systemProxyActive here is safe: stopMetaAndDisableTun
        // only stops the Meta process and disables TUN, it does NOT touch the system
        // proxy. NetworkChangeNotifier probes are live reads; stopTask doesn't affect
        // their result either.
        let decision = proxyCleanupDecision()

        async let stopTask = stopMetaAndDisableTun(timeout: shouldForce ? forceTimeout : normalTimeout)

        removeTempFiles()

        guard decision.shouldClean else {
            _ = await stopTask
            Logger.log("ClashX quit without clean waiting")
            return true
        }

        Logger.log("ClashX quit need clean proxy setting")
        prepareForTerminationWait()

        _ = await stopTask
        Logger.log("ClashX quit wait for clean up")

        let finished = await performProxyCleanup(forceDisable: decision.force, timeout: shouldForce ? forceTimeout : normalTimeout)
        if finished {
            Logger.log("ClashX quit after clean up finish")
        } else {
            Logger.log("ClashX quit after clean up timeout")
        }

        return true
    }

    @MainActor
    func handleWillTerminate() async {
        UserDefaults.standard.set(0, forKey: "launch_fail_times")
        Logger.log("ClashX will terminate")
        ApiRequest.shared.prepareForTermination()
    }

    // MARK: - Private

    @MainActor
    private func confirmAction() -> Bool {
        if NSApp.activationPolicy() == .regular {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Quit ClashX?", comment: "")
            alert.informativeText = NSLocalizedString("The active connections will be interrupted.", comment: "")
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
            return alert.runModal() == .alertFirstButtonReturn
        }
        return true
    }

    private func stopMetaAndDisableTun(timeout: TimeInterval) async {
        let cancelled = ManagedAtomic<Bool>(false)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline, !cancelled.load(ordering: .relaxed) {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if !cancelled.load(ordering: .relaxed) {
                    cancelled.store(true, ordering: .relaxed)
                    continuation.resume()
                }
            }
            Task {
                try? await PrivilegedHelperManager.shared.request(
                    ProxyConfigHelperMessages.StopMeta())
                await ProxyManager.shared.disableTunForTermination()
                if !cancelled.load(ordering: .relaxed) {
                    cancelled.store(true, ordering: .relaxed)
                    continuation.resume()
                }
            }
        }
    }

    private func removeTempFiles() {
        try? FileManager.default.removeItem(atPath: Paths.cacheConfigs())
        try? FileManager.default.removeItem(atPath: Paths.localConfigPath(for: kSafeConfigName))
    }

    /// Determines whether system-proxy cleanup is needed on exit and whether to force-disable.
    ///
    /// - `shouldClean`: true if the system proxy is currently active OR if any network
    ///   interface has ClashX-bound proxy (proactively cleanup stale state).
    /// - `force`: true when the proxy was last modified by another app (takeover case).
    ///   When `force == true`, cleanup uses DisableProxy (clear all proxy) rather than
    ///   RestoreProxy (which would replay a saved proxy snapshot that wasn't ours to restore).
    private func proxyCleanupDecision() -> (shouldClean: Bool, force: Bool) {
        let state = ProxyManager.shared.runtimeState
        let shouldClean =
            state.systemProxyActive ||
            NetworkChangeNotifier.isCurrentSystemSetToClash(looser: true) ||
            NetworkChangeNotifier.hasInterfaceProxySetToClash()

        let force = state.systemProxySetByOther
        return (shouldClean, force)
    }

    private func prepareForTerminationWait() {
        if let statusItem = AppDelegate.shared.statusItem, statusItem.menu != nil {
            statusItem.menu = nil
        }
        AppDelegate.shared.disposeBag = DisposeBag()
    }

    private func performProxyCleanup(forceDisable: Bool, timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                await ProxyManager.shared.disableAllProxiesForTermination(force: forceDisable)
                return true
            }
            group.addTask {
                try? await Task.sleep(seconds: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
