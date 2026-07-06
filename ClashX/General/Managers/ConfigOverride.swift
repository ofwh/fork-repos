//
//  ConfigOverride.swift
//  ClashX
//

import Foundation
import Yams

final class ConfigOverride {
    static let shared = ConfigOverride()

    private init() {}

    // MARK: - Always Override

    var logLevel: ClashLogLevel {
        get { ClashLogLevel(rawValue: UserDefaults.standard.string(forKey: "selectLoggingApiLevel") ?? "") ?? .info }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectLoggingApiLevel") }
    }

    // MARK: - Optional Override

    var allowLan: Bool? {
        get { UserDefaults.standard.object(forKey: "allowConnectFromLan") as? Bool }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: "allowConnectFromLan")
            } else {
                UserDefaults.standard.removeObject(forKey: "allowConnectFromLan")
            }
        }
    }

    var mode: ClashProxyMode {
        get { ClashProxyMode(rawValue: UserDefaults.standard.string(forKey: "selectOutBoundMode") ?? "") ?? .rule }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectOutBoundMode") }
    }

    // MARK: - Forced Default Override

    var snifferEnable: Bool? {
        get { UserDefaults.standard.object(forKey: "overrideSnifferEnable") as? Bool }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: "overrideSnifferEnable")
            } else {
                UserDefaults.standard.removeObject(forKey: "overrideSnifferEnable")
            }
        }
    }

    @MainActor
    var tunEnable: Bool? {
        let intent = ProxyManager.shared.state.intent
        return intent.tunOverridden ? intent.tunEnabled : nil
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
        if let allowLan = allowLan {
            yaml["allow-lan"] = .init("\(allowLan)")
        }
        yaml["mode"] = .init(mode.rawValue)
        yaml["log-level"] = .init(logLevel.rawValue)

        applySnifferOverride(&yaml)
        applyTunOverride(&yaml)
    }

    private func applySnifferOverride(_ yaml: inout Node) {
        if yaml["sniffer"] != nil {
            if let snifferEnable = snifferEnable {
                yaml["sniffer"]!["enable"] = .init("\(snifferEnable)")
            }
        } else {
            yaml["sniffer"] = [
                "enable": .init("\(snifferEnable ?? false)"),
                "sniff": [
                    "HTTP": [
                        "ports": ["80", "8080-8880"],
                        "override-destination": "true",
                    ],
                    "TLS": [
                        "ports": ["443", "8443"],
                    ],
                    "QUIC": [
                        "ports": ["443", "8443"],
                    ],
                ],
                "skip-domain": [
                    "Mijia Cloud",
                    "+.push.apple.com",
                ],
            ]
        }
    }

    @MainActor
    private func applyTunOverride(_ yaml: inout Node) {
        if yaml["tun"] != nil {
            if let tunEnable = tunEnable {
                yaml["tun"]!["enable"] = .init("\(tunEnable)")
            }
        } else {
            yaml["tun"] = [
                "enable": .init("\(tunEnable ?? false)"),
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
