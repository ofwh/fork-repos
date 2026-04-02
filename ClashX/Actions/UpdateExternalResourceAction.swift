//
//  UpdateExternalResourceAction.swift
//  ClashX
//
//  Created by yicheng on 2023/9/4.
//  Copyright © 2023 west2online. All rights reserved.
//

import Foundation
enum UpdateExternalResourceAction {
    static func run() async {
        let provider = await ApiRequest.requestExternalProviderNames()
        let totalCount = provider.proxies.count + provider.rules.count
        if totalCount == 0 {
            onFinished(success: 0, total: 0, fails: [])
            return
        }

        let results = await withTaskGroup(of: (String, Bool).self, returning: [(String, Bool)].self) { group in
            for name in provider.proxies {
                group.addTask {
                    (name, await ApiRequest.updateProvider(for: .proxy, name: name))
                }
            }

            for name in provider.rules {
                group.addTask {
                    (name, await ApiRequest.updateProvider(for: .rule, name: name))
                }
            }

            var results = [(String, Bool)]()
            for await result in group {
                results.append(result)
            }
            return results
        }

        let successCount = results.filter(\.1).count
        let fails = results.filter { !$0.1 }.map(\.0)
        onFinished(success: successCount, total: totalCount, fails: fails)
    }

    private static func onFinished(success: Int, total: Int, fails: [String]) {
        var info = String(format: NSLocalizedString("total: %d, success: %d", comment: ""), total, success)
        if !fails.isEmpty {
            info.append(String(format: NSLocalizedString("fails: %@", comment: ""), fails.joined(separator: " ")))
        }
		UserNotificationCenter.shared.post(title: NSLocalizedString("Update external resource complete", comment: ""), info: info)
    }
}
