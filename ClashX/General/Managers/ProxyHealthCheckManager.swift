//
//  ProxyHealthCheckManager.swift
//  ClashX
//

import Cocoa

@MainActor
final class ProxyHealthCheckManager {
    static let shared = ProxyHealthCheckManager()

    private var isSpeedTesting = false

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
