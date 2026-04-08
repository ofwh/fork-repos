//
//  ConfigManager.swift
//  ClashX
//
//  Created by CYC on 2018/6/12.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa
import Foundation
import RxCocoa
import RxSwift

class ConfigManager {
    static let shared = ConfigManager()
    private let disposeBag = DisposeBag()
    var apiPort = "8080"
    var allowExternalControl = false
    var apiSecret: String = ""
    var overrideApiURL: URL?
    var overrideSecret: String?

    var currentConfig: ClashConfig? {
        get {
            return currentConfigVariable.value
        }

        set {
            currentConfigVariable.accept(newValue)
        }
    }

    var currentConfigVariable = BehaviorRelay<ClashConfig?>(value: nil)

    var isRunning: Bool {
        get {
            return isRunningVariable.value
        }

        set {
            isRunningVariable.accept(newValue)
			NotificationCenter.default.post(.init(name: .init("ClashRunningStateChanged")))
        }
    }

    static var selectConfigName: String {
        get {
            return UserDefaults.standard.string(forKey: "selectConfigName") ?? "config"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "selectConfigName")
            Task {
                await watchCurrentConfigFile()
            }
        }
    }

    @MainActor
    static func watchCurrentConfigFile() async {
        if ICloudManager.shared.useiCloud.value {
            guard let url = await ICloudManager.shared.getUrl() else { return }
            let configUrl = url.appendingPathComponent(Paths.configFileName(for: selectConfigName))
            ConfigFileManager.shared.watchFile(path: configUrl.path)
        } else {
            ConfigFileManager.shared.watchFile(path: Paths.localConfigPath(for: selectConfigName))
        }
    }

    let isRunningVariable = BehaviorRelay<Bool>(value: false)

    var proxyPortAutoSet: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "proxyPortAutoSet")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "proxyPortAutoSet")
        }
    }
	
	var restoreSystemProxy: Bool {
		get {
			return UserDefaults.standard.bool(forKey: "restoreSystemProxy")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "restoreSystemProxy")
		}
	}
	
	var restoreTunProxy: Bool {
		get {
			return UserDefaults.standard.bool(forKey: "restoreTunProxy")
		}
		set {
			UserDefaults.standard.set(newValue, forKey: "restoreTunProxy")
		}
	}

    let proxyPortAutoSetObservable = UserDefaults.standard.rx.observe(Bool.self, "proxyPortAutoSet").map { $0 ?? false }

    var isProxySetByOtherVariable = BehaviorRelay<Bool>(value: false)
    var proxyShouldPaused = BehaviorRelay<Bool>(value: false)

    var isTunModeVariable = BehaviorRelay<Bool>(value: false)
    var isTunModeInConfig = false
	
	static let defaultTunDNS = "8.8.8.8"
	
	static var metaTunDNS: String = UserDefaults.standard.object(forKey: "metaTunDNS") as? String ?? defaultTunDNS {
		didSet {
			UserDefaults.standard.set(metaTunDNS, forKey: "metaTunDNS")
		}
	}

    var showNetSpeedIndicator: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "showNetSpeedIndicator")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showNetSpeedIndicator")
        }
    }

    let showNetSpeedIndicatorObservable = UserDefaults.standard.rx.observe(Bool.self, "showNetSpeedIndicator")

    var benchMarkUrl: String = UserDefaults.standard.string(forKey: "benchMarkUrl") ?? "http://cp.cloudflare.com/generate_204" {
        didSet {
            UserDefaults.standard.set(benchMarkUrl, forKey: "benchMarkUrl")
        }
    }

    static var apiUrl: String {
        if let override = shared.overrideApiURL {
            return override.absoluteString
        }
        return "http://127.0.0.1:\(shared.apiPort)"
    }

    static var webSocketUrl: String {
        if let override = shared.overrideApiURL, var comp = URLComponents(url: override, resolvingAgainstBaseURL: true) {
            if comp.scheme == "https" {
                comp.scheme = "wss"
            } else {
                comp.scheme = "ws"
            }
            return comp.url?.absoluteString ?? ""
        }
        return "ws://127.0.0.1:\(shared.apiPort)"
    }

    static var selectedProxyRecords = SavedProxyModel.loadsFromUserDefault() {
        didSet {
            SavedProxyModel.save(selectedProxyRecords)
        }
    }

    static var selectOutBoundMode: ClashProxyMode {
        get {
            return ClashProxyMode(rawValue: UserDefaults.standard.string(forKey: "selectOutBoundMode") ?? "") ?? .rule
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectOutBoundMode")
        }
    }

    static var allowConnectFromLan: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "allowConnectFromLan")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "allowConnectFromLan")
        }
    }

    static var selectLoggingApiLevel: ClashLogLevel {
        get {
            return ClashLogLevel(rawValue: UserDefaults.standard.string(forKey: "selectLoggingApiLevel") ?? "") ?? .info
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectLoggingApiLevel")
        }
    }

    var disableShowCurrentProxyInMenu: Bool = UserDefaults.standard.object(forKey: "kSDisableShowCurrentProxyInMenu") as? Bool ?? !AppDelegate.isAboveMacOS14 {
        didSet {
            UserDefaults.standard.set(disableShowCurrentProxyInMenu, forKey: "kSDisableShowCurrentProxyInMenu")
        }
    }

    static func getConfigPath(configName: String) async -> String? {
        if ICloudManager.shared.useiCloud.value {
            guard let url = await ICloudManager.shared.getUrl() else {
                return nil
            }
            return url.appendingPathComponent(Paths.configFileName(for: configName)).path
        } else {
            return Paths.localConfigPath(for: configName)
        }
    }
}

extension ConfigManager {
    static func getConfigFilesList() -> [String] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(atPath: kConfigFolderPath)
            return fileURLs
                .filter { String($0.split(separator: ".").last ?? "") == "yaml" }
                .map { $0.split(separator: ".").dropLast().joined(separator: ".") }
        } catch {
            return ["config"]
        }
    }
}

enum WebDashboard: String {
    case yacd
    case metacubexd
    case zashboard
}

extension ConfigManager {
    static var webDashboard: WebDashboard {
        get {
            guard let string = UserDefaults.standard.object(forKey: "webDashboard") as? String,
                  let dashboard = WebDashboard(rawValue: string) else {
                return .zashboard
            }
            return dashboard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "webDashboard")
        }
    }
	
	static var useSwiftUIDashboard: Bool = UserDefaults.standard.object(forKey: "useSwiftUIDashboard") as? Bool ?? false {
		didSet {
			UserDefaults.standard.set(useSwiftUIDashboard, forKey: "useSwiftUIDashboard")
		}
	}
	
	static var useAlphaCore: Bool = UserDefaults.standard.object(forKey: "useAlphaCore") as? Bool ?? false {
		didSet {
			UserDefaults.standard.set(useAlphaCore, forKey: "useAlphaCore")
		}
	}
}
