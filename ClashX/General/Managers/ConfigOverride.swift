//
//  ConfigOverride.swift
//  ClashX
//

import Foundation
import Yams

final class ConfigOverride {
    static let shared = ConfigOverride()

    private init() {}

    // MARK: - Settings (UserDefaults)

    var allowLan: Bool {
        get { UserDefaults.standard.bool(forKey: "allowConnectFromLan") }
        set { UserDefaults.standard.set(newValue, forKey: "allowConnectFromLan") }
    }

    var mode: ClashProxyMode {
        get { ClashProxyMode(rawValue: UserDefaults.standard.string(forKey: "selectOutBoundMode") ?? "") ?? .rule }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectOutBoundMode") }
    }

    var logLevel: ClashLogLevel {
        get { ClashLogLevel(rawValue: UserDefaults.standard.string(forKey: "selectLoggingApiLevel") ?? "") ?? .info }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectLoggingApiLevel") }
    }

    var snifferEnable: Bool {
        get { UserDefaults.standard.object(forKey: "overrideSnifferEnable") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "overrideSnifferEnable") }
    }

    @MainActor
    var tunEnable: Bool {
        ProxyManager.shared.state.intent.tunEnabled
    }

    func composeConfig(configName: String) async -> String? {
        guard let configPath = await ApiRequest.findConfigPath(configName: configName),
              let yamlString = readFileString(configPath),
              var yaml = try? Yams.compose(yaml: yamlString) else {
            return nil
        }

        await applyOverrides(&yaml)

        guard let result = try? Yams.serialize(node: yaml),
              let path = RemoteConfigManager.createCacheConfig(string: result) else {
            return nil
        }
        return path
    }

    @MainActor
    func applyOverrides(_ yaml: inout Node) {
        yaml["allow-lan"] = .init("\(allowLan)")
        yaml["mode"] = .init(mode.rawValue)
        yaml["log-level"] = .init(logLevel.rawValue)

        applySnifferOverride(&yaml)
        applyTunOverride(&yaml)
    }

    private func applySnifferOverride(_ yaml: inout Node) {
        if yaml["sniffer"] != nil {
            yaml["sniffer"]!["enable"] = .init("\(snifferEnable)")
        } else {
            yaml["sniffer"] = ["enable": .init("\(snifferEnable)")]
        }
    }

    @MainActor
    private func applyTunOverride(_ yaml: inout Node) {
        if yaml["tun"] != nil {
            yaml["tun"]!["enable"] = .init("\(tunEnable)")
        } else {
            yaml["tun"] = [
                "enable": .init("\(tunEnable)"),
                "auto-route": "true",
                "auto-detect-interface": "true",
                "dns-hijack": [
                    "any:53",
                    "tcp://any:53"
                ],
            ]
        }
    }

    private func readFileString(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
