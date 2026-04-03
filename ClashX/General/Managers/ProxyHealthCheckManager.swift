//
//  ProxyHealthCheckManager.swift
//  ClashX
//

import Cocoa
import RxCocoa
import RxSwift

@MainActor
final class ProxyHealthCheckManager {
    static let shared = ProxyHealthCheckManager()

    private var isSpeedTesting = false
    private var ipAddressChangeTask: Task<Void, Never>?

    private init() {}

    func healthCheck(proxy name: ClashProxyName) async {
        await ApiRequest.healthCheck(proxy: name)
    }

    func getGroupDelay(groupName: ClashProxyName) async -> [String: Int] {
        await ApiRequest.getGroupDelay(groupName: groupName)
    }

    func healthCheckOnNetworkChange() async {
        let proxyResp = await ApiRequest.getMergedProxyData()
        let groups = proxyResp.proxyGroups.filter(\.type.isAutoGroup)
        var providers = Set<ClashProxyName>()

        groups.forEach { group in
            group.all?.compactMap {
                proxyResp.proxiesMap[$0]?.enclosingProvider?.name
            }.forEach {
                providers.insert($0)
            }
        }

        for group in groups {
            Logger.log("Start auto health check for group \(group.name)")
            await healthCheck(proxy: group.name)
        }

        for provider in providers {
            Logger.log("Start auto health check for provider \(provider)")
            await healthCheck(proxy: provider)
        }
    }

    func setupHealthCheckOnIPAddressChange(disposeBag _: DisposeBag) {
        guard ipAddressChangeTask == nil else { return }

        ipAddressChangeTask = Task { @MainActor in
            var previousIPAddress = NetworkChangeNotifier.getPrimaryIPAddress(allowIPV6: false)
            var debounceTask: Task<Void, Never>?

            defer {
                debounceTask?.cancel()
            }

            for await currentIPAddress in NetworkChangeNotifier.ipAddressStream(allowIPV6: false) {
                guard !Task.isCancelled else { return }
                guard let currentIPAddress, currentIPAddress != previousIPAddress else { continue }

                previousIPAddress = currentIPAddress
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(seconds: 5)
                    guard !Task.isCancelled else { return }
                    await ProxyHealthCheckManager.shared.healthCheckOnNetworkChange()
                }
            }
        }
    }

    func runSpeedTest() async {
        if isSpeedTesting {
            UserNotificationCenter.shared.postSpeedTestingNotice()
            return
        }

        UserNotificationCenter.shared.postSpeedTestBeginNotice()
        isSpeedTesting = true
        defer {
            UserNotificationCenter.shared.postSpeedTestFinishNotice()
            isSpeedTesting = false
        }

        let resp = await ApiRequest.getMergedProxyData()

        await withTaskGroup(of: Void.self) { group in
            resp.enclosingProviderResp?.providers.forEach { name, _ in
                group.addTask {
                    await self.healthCheck(proxy: name)
                }
            }

            resp.proxiesMap["GLOBAL"]?.all?.forEach { proxy in
                group.addTask {
                    _ = await ApiRequest.getProxyDelay(proxyName: proxy)
                }
            }
        }
    }
}
