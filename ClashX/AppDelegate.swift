//
//  AppDelegate.swift
//  ClashX
//
//  Created by CYC on 2018/6/10.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Alamofire
import Cocoa
import RxCocoa
import RxSwift
import SwiftyJSON
import Yams

let statusItemLengthWithSpeed: CGFloat = 72

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItem: NSStatusItem!

    @IBOutlet var statusMenu: NSMenu!
    @IBOutlet var proxySettingMenuItem: NSMenuItem!
    @IBOutlet var autoStartMenuItem: NSMenuItem!

    @IBOutlet var proxyModeGlobalMenuItem: NSMenuItem!
    @IBOutlet var proxyModeDirectMenuItem: NSMenuItem!
    @IBOutlet var proxyModeRuleMenuItem: NSMenuItem!
    @IBOutlet var allowFromLanMenuItem: NSMenuItem!

    @IBOutlet var proxyModeMenuItem: NSMenuItem!
    @IBOutlet var showNetSpeedIndicatorMenuItem: NSMenuItem!
    @IBOutlet var dashboardMenuItem: NSMenuItem!
    @IBOutlet var separatorLineTop: NSMenuItem!
    @IBOutlet var sepatatorLineEndProxySelect: NSMenuItem!
    @IBOutlet var configSeparatorLine: NSMenuItem!
    @IBOutlet var logLevelMenuItem: NSMenuItem!
    @IBOutlet var httpPortMenuItem: NSMenuItem!
    @IBOutlet var socksPortMenuItem: NSMenuItem!
    @IBOutlet var apiPortMenuItem: NSMenuItem!
    @IBOutlet var ipMenuItem: NSMenuItem!
    @IBOutlet var remoteConfigAutoupdateMenuItem: NSMenuItem!
    @IBOutlet var copyExportCommandMenuItem: NSMenuItem!
    @IBOutlet var copyExportCommandExternalMenuItem: NSMenuItem!
    @IBOutlet var externalControlSeparator: NSMenuItem!
    @IBOutlet var connectionsMenuItem: NSMenuItem!

    @IBOutlet var tunModeMenuItem: NSMenuItem!

    @IBOutlet var proxyProvidersMenu: NSMenu!
    @IBOutlet var ruleProvidersMenu: NSMenu!
    @IBOutlet var proxyProvidersMenuItem: NSMenuItem!
    @IBOutlet var ruleProvidersMenuItem: NSMenuItem!
    @IBOutlet var snifferMenuItem: NSMenuItem!
    @IBOutlet var flushFakeipCacheMenuItem: NSMenuItem!

    var disposeBag = DisposeBag()
    var statusItemView: StatusItemViewProtocol!
    var isSpeedTesting = false

    var runAfterConfigReload: (() -> Void)?
	
	var updateGeoTimer: Timer?
	
    let clashProcess = ClashProcess()

    func applicationWillFinishLaunching(_ notification: Notification) {
        Logger.log("applicationWillFinishLaunching")
        signal(SIGPIPE, SIG_IGN)
        // crash recorder
        failLaunchProtect()
        NSAppleEventManager.shared()
            .setEventHandler(self,
                             andSelector: #selector(handleURL(event:reply:)),
                             forEventClass: AEEventClass(kInternetEventClass),
                             andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("———————————————————————————————————————————————————————————")
        Logger.log("———————————————applicationDidFinishLaunching———————————————")
        Logger.log("———————————————————————————————————————————————————————————")
        Logger.log("Appversion: \(AppVersionUtil.currentVersion) \(AppVersionUtil.currentBuild)")
        ProcessInfo.processInfo.disableSuddenTermination()
        // setup menu item first
        statusItem = NSStatusBar.system.statusItem(withLength: statusItemLengthWithSpeed)
        statusItemView = StatusItemView.create(statusItem: statusItem)
        statusItemView.updateSize(width: statusItemLengthWithSpeed)
        statusMenu.delegate = self
        setupStatusMenuItemData()
        DispatchQueue.main.async {
            self.postFinishLaunching()
        }
    }

    func postFinishLaunching() {
        Logger.log("postFinishLaunching")
        defer {
            statusItem.menu = statusMenu
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                self.checkMenuIconVisable()
            }
        }
        if #unavailable(macOS 10.15) {
            // dashboard is not support in macOS 10.15 below
            self.dashboardMenuItem.isHidden = true
            self.connectionsMenuItem.isHidden = true
        }
        AppVersionUtil.showUpgradeAlert()
        ICloudManager.shared.setup()

        if WebPortalManager.hasWebProtal {
            WebPortalManager.shared.addWebProtalMenuItem(&statusMenu)
        }
		
        // install proxy helper
        _ = ClashResourceManager.check()
        Task {
            await PrivilegedHelperManager.shared.checkInstall()
        }
        ConfigFileManager.copySampleConfigIfNeed()

        // claer not existed selected model
        removeUnExistProxyGroups()
        setupData()
        runAfterConfigReload = { [weak self] in
            Task {
                await self?.selectAllowLanWithMenory()
            }
        }

        updateLoggingLevel()

        // start watch config file change
        ConfigManager.watchCurrentConfigFile()

        RemoteConfigManager.shared.autoUpdateCheck()

        setupNetworkNotifier()
        registCrashLogger()
        KeyboardShortCutManager.setup()
        RemoteControlManager.setupMenuItem(separator: externalControlSeparator)
    }

    
    
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return TerminalConfirmAction.run()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        UserDefaults.standard.set(0, forKey: "launch_fail_times")
        Logger.log("ClashX will terminate")
        if NetworkChangeNotifier.isCurrentSystemSetToClash(looser: true) ||
            NetworkChangeNotifier.hasInterfaceProxySetToClash() {
            Logger.log("Need Reset Proxy Setting again", level: .error)
            Task {
                await SystemProxyManager.shared.disableProxy()
            }
        }
    }

    func checkMenuIconVisable() {
        guard let button = statusItem.button else { assertionFailure(); return }
        guard let window = button.window else { assertionFailure(); return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let onScreenRect = window.convertToScreen(buttonRect)
        var leftScreenX: CGFloat = 0
        for screen in NSScreen.screens where screen.frame.origin.x < leftScreenX {
            leftScreenX = screen.frame.origin.x
        }
        let isMenuIconHidden = onScreenRect.midX < leftScreenX

        var isCoverdByNotch = false
        if #available(macOS 12, *), NSScreen.screens.count == 1, let screen = NSScreen.screens.first, let leftArea = screen.auxiliaryTopLeftArea, let rightArea = screen.auxiliaryTopRightArea {
            if onScreenRect.minX > leftArea.maxX, onScreenRect.maxX < rightArea.minX {
                isCoverdByNotch = true
            }
        }

        Logger.log("checkMenuIconVisable: \(onScreenRect) \(leftScreenX), hidden: \(isMenuIconHidden), coverd by notch:\(isCoverdByNotch)")

        if isMenuIconHidden || isCoverdByNotch, !Settings.disableMenubarNotice {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("The status icon is coverd or hide by other app.", comment: "")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Never show again", comment: ""))
            if alert.runModal() == .alertSecondButtonReturn {
                Settings.disableMenubarNotice = true
            }
        }
    }

    func setupStatusMenuItemData() {
        ConfigManager.shared
            .showNetSpeedIndicatorObservable
            .bind { [weak self] show in
                guard let self = self else { return }
                self.showNetSpeedIndicatorMenuItem.state = (show ?? true) ? .on : .off
                let statusItemLength: CGFloat = (show ?? true) ? statusItemLengthWithSpeed : 25
                self.statusItem.length = statusItemLength
                self.statusItemView.updateSize(width: statusItemLength)
                self.statusItemView.showSpeedContainer(show: show ?? true)
            }.disposed(by: disposeBag)

        statusItemView.updateViewStatus(enableProxy: ConfigManager.shared.proxyPortAutoSet)

    }
	
    func setupData() {
        ConfigManager.shared
            .showNetSpeedIndicatorObservable.skip(1)
            .bind {
                _ in
                ApiRequest.shared.resetTrafficStreamApi()
            }.disposed(by: disposeBag)

        Observable
            .merge([ConfigManager.shared.proxyPortAutoSetObservable,
                    ConfigManager.shared.isProxySetByOtherVariable.asObservable(),
                    ConfigManager.shared.proxyShouldPaused.asObservable()])
            .observe(on: MainScheduler.instance)
            .map { _ -> NSControl.StateValue in
                if (ConfigManager.shared.isProxySetByOtherVariable.value || ConfigManager.shared.proxyShouldPaused.value) && ConfigManager.shared.proxyPortAutoSet {
                    return .mixed
                }
                return ConfigManager.shared.proxyPortAutoSet ? .on : .off
            }.distinctUntilChanged()
            .bind { [weak self] status in
                guard let self = self else { return }
                self.proxySettingMenuItem.state = status
            }.disposed(by: disposeBag)

        Observable
            .merge([ConfigManager.shared.proxyPortAutoSetObservable,
                    ConfigManager.shared.isTunModeVariable.asObservable(),
                    ConfigManager.shared.isProxySetByOtherVariable.asObservable()])
            .map { _ -> Bool in
                var status = NSControl.StateValue.mixed
                if ConfigManager.shared.isProxySetByOtherVariable.value && ConfigManager.shared.proxyPortAutoSet {

                } else {
                    status = ConfigManager.shared.proxyPortAutoSet ? .on : .off
                }
                return status == .on || ConfigManager.shared.isTunModeVariable.value
            }.distinctUntilChanged()
            .bind { [weak self] enable in
                guard let self = self else { return }
                self.statusItemView.updateViewStatus(enableProxy: enable)
            }.disposed(by: disposeBag)

        let configObservable = ConfigManager.shared
            .currentConfigVariable
            .asObservable()
        Observable.zip(configObservable, configObservable.skip(1))
            .filter { _, new in return new != nil }
            .observe(on: MainScheduler.instance)
            .bind { [weak self] old, config in
                guard let self = self, let config = config else { return }
                self.proxyModeDirectMenuItem.state = .off
                self.proxyModeGlobalMenuItem.state = .off
                self.proxyModeRuleMenuItem.state = .off

                switch config.mode {
                case .direct: self.proxyModeDirectMenuItem.state = .on
                case .global: self.proxyModeGlobalMenuItem.state = .on
                case .rule: self.proxyModeRuleMenuItem.state = .on
                }
                self.allowFromLanMenuItem.state = config.allowLan ? .on : .off

                self.proxyModeMenuItem.title = "\(NSLocalizedString("Proxy Mode", comment: "")) (\(config.mode.name))"

                if old?.usedHttpPort != config.usedHttpPort || old?.usedSocksPort != config.usedSocksPort {
                    Logger.log("port config updated,new: \(config.usedHttpPort),\(config.usedSocksPort)")
                    if ConfigManager.shared.proxyPortAutoSet {
                        Task {
                            await SystemProxyManager.shared.enableProxy(port: config.usedHttpPort, socksPort: config.usedSocksPort)
                        }
                    }
                }

                self.httpPortMenuItem.title = "Http Port: \(config.usedHttpPort)"
                self.socksPortMenuItem.title = "Socks Port: \(config.usedSocksPort)"
                self.apiPortMenuItem.title = "Api Port: \(ConfigManager.shared.apiPort)"
                self.ipMenuItem.title = "IP: \(NetworkChangeNotifier.getPrimaryIPAddress() ?? "")"

                if RemoteControlManager.selectConfig == nil {
                    ClashStatusTool.checkPortConfig(cfg: config)
                }

                self.snifferMenuItem.state = config.sniffing ? .on : .off
                self.tunModeMenuItem.state = config.tun.enable ? .on : .off
                ConfigManager.shared.isTunModeVariable.accept(config.tun.enable)
            }.disposed(by: disposeBag)
		
		if !PrivilegedHelperManager.shared.isHelperCheckFinished.value {
			proxySettingMenuItem.target = nil
			tunModeMenuItem.target = nil
			PrivilegedHelperManager.shared.isHelperCheckFinished
				.filter({$0})
				.take(1)
				.observe(on: MainScheduler.instance)
				.subscribe { [weak self] _ in
					guard let self = self else { return }
					self.proxySettingMenuItem.target = self
					self.tunModeMenuItem.target = self
                    Task {
                        await self.startProxyCore()
                    }
				}.disposed(by: disposeBag)
		} else {
			self.proxySettingMenuItem.target = self
			self.tunModeMenuItem.target = self
            Task {
                await startProxyCore()
            }
		}

        LaunchAtLogin.shared
            .isEnableVirable
            .asObservable()
            .subscribe(onNext: { [weak self] enable in
                guard let self = self else { return }
                self.autoStartMenuItem.state = enable ? .on : .off
            }).disposed(by: disposeBag)

        remoteConfigAutoupdateMenuItem.state = RemoteConfigManager.autoUpdateEnable ? .on : .off

    }

    func setupNetworkNotifier() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            NetworkChangeNotifier.start()
        }

        NotificationCenter
            .default
            .rx
            .notification(.systemNetworkStatusDidChange)
            .observe(on: MainScheduler.instance)
            .delay(.milliseconds(200), scheduler: MainScheduler.instance)
            .bind { _ in
                guard NetworkChangeNotifier.getPrimaryInterface() != nil else { return }
                let proxySetted = NetworkChangeNotifier.isCurrentSystemSetToClash()
                ConfigManager.shared.isProxySetByOtherVariable.accept(!proxySetted)
                if !proxySetted && ConfigManager.shared.proxyPortAutoSet {
                    let proxiesSetting = NetworkChangeNotifier.getRawProxySetting()
                    Logger.log("Proxy changed by other process!, current:\(proxiesSetting), is Interface Set: \(NetworkChangeNotifier.hasInterfaceProxySetToClash())", level: .warning)
                }
            }.disposed(by: disposeBag)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(resetProxySettingOnWakeupFromSleep),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        NotificationCenter
            .default
            .rx
            .notification(.systemNetworkStatusIPUpdate).map { _ in
                NetworkChangeNotifier.getPrimaryIPAddress(allowIPV6: false)
            }
            .startWith(NetworkChangeNotifier.getPrimaryIPAddress(allowIPV6: false))
            .distinctUntilChanged()
            .skip(1)
            .filter { $0 != nil }
            .observe(on: MainScheduler.instance)
            .debounce(.seconds(5), scheduler: MainScheduler.instance).bind { [weak self] _ in
                self?.healthCheckOnNetworkChange()
            }.disposed(by: disposeBag)

        ConfigManager.shared
            .isProxySetByOtherVariable
            .asObservable()
            .filter { _ in ConfigManager.shared.proxyPortAutoSet }
            .distinctUntilChanged()
            .filter { $0 }
            .filter { _ in !ConfigManager.shared.proxyShouldPaused.value }
            .bind { _ in
                let rawProxy = NetworkChangeNotifier.getRawProxySetting()
                Logger.log("proxy changed to no clashX setting: \(rawProxy)", level: .warning)
				UserNotificationCenter.shared.postProxyChangeByOtherAppNotice()
            }.disposed(by: disposeBag)

        NotificationCenter
            .default
            .rx
            .notification(.systemNetworkStatusIPUpdate).map { _ in
                NetworkChangeNotifier.getPrimaryIPAddress(allowIPV6: false)
            }.bind { [weak self] _ in
                if RemoteControlManager.selectConfig != nil {
                    self?.resetStreamApi()
                }
            }.disposed(by: disposeBag)
    }

    func updateProxyList(withMenus menus: [NSMenuItem]) {
        let startIndex = statusMenu.items.firstIndex(of: separatorLineTop)! + 1
        let endIndex = statusMenu.items.firstIndex(of: sepatatorLineEndProxySelect)!
        sepatatorLineEndProxySelect.isHidden = menus.isEmpty
        for _ in 0 ..< endIndex - startIndex {
            statusMenu.removeItem(at: startIndex)
        }
        for each in menus {
            statusMenu.insertItem(each, at: startIndex)
        }
    }

    @MainActor
    func updateConfigFiles() async {
        guard let menu = configSeparatorLine.menu else { return }
        let items = await MenuItemFactory.generateSwitchConfigMenuItems()
        let lineIndex = menu.items.firstIndex(of: self.configSeparatorLine)!
        for _ in 0 ..< lineIndex {
            menu.removeItem(at: 0)
        }
        for item in items.reversed() {
            menu.insertItem(item, at: 0)
        }
    }

    func updateLoggingLevel() {
        Task {
            _ = await ApiRequest.updateLogLevel(level: ConfigManager.selectLoggingApiLevel)
        }
        for item in logLevelMenuItem.submenu?.items ?? [] {
            item.state = item.title.lowercased() == ConfigManager.selectLoggingApiLevel.rawValue ? .on : .off
        }
        NotificationCenter.default.post(name: .reloadDashboard, object: nil)
    }

    @MainActor
    func syncConfig() async {
        guard let config = await ApiRequest.requestConfig() else { return }
        ConfigManager.shared.currentConfig = config
    }

    @MainActor
    func syncConfigWithTun(_ isInit: Bool = false) async {
        await syncConfig()

        guard let config = ConfigManager.shared.currentConfig else { return }

        let enable = config.tun.enable

        if isInit, !enable {
            Logger.log("tun didn't set")
            return
        }

        try? await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.UpdateTun(state: enable, dns: ConfigManager.metaTunDNS))
        Logger.log("tun state updated, new: \(enable)")
    }

    func resetStreamApi() {
        ApiRequest.shared.delegate = self
        ApiRequest.shared.resetStreamApis()
    }

    @MainActor
    func updateConfig(configName: String? = nil, showNotification: Bool = true) async -> ErrorString? {
		await startProxyCore()
        guard ConfigManager.shared.isRunning else { return nil }

        let config = configName ?? ConfigManager.selectConfigName

        ClashProxy.cleanCache()

        let err = await ApiRequest.requestConfigUpdate(configName: config)

        if let err {
            UpdateConfigAction.showError(text: err, configName: config)
            return err
        }

        await syncConfigWithTun()
        resetStreamApi()
        runAfterConfigReload?()
        runAfterConfigReload = nil
        if showNotification {
			UserNotificationCenter.shared.post(
				title: NSLocalizedString("Reload Config Succeed", comment: ""),
				info: NSLocalizedString("Success", comment: ""))
        }

        if let newConfigName = configName {
            ConfigManager.selectConfigName = newConfigName
        }
        selectProxyGroupWithMemory()
        await selectOutBoundModeWithMenory()
        await MenuItemFactory.recreateProxyMenuItems()
        NotificationCenter.default.post(name: .reloadDashboard, object: nil)
        return nil
    }


    @objc func resetProxySettingOnWakeupFromSleep() {
        guard !ConfigManager.shared.isProxySetByOtherVariable.value,
              ConfigManager.shared.proxyPortAutoSet else { return }
        guard NetworkChangeNotifier.getPrimaryInterface() != nil else { return }
        if !NetworkChangeNotifier.isCurrentSystemSetToClash() {
            let rawProxy = NetworkChangeNotifier.getRawProxySetting()
            Logger.log("Resting proxy setting, current:\(rawProxy)", level: .warning)
            Task {
                await SystemProxyManager.shared.disableProxy()
                await SystemProxyManager.shared.enableProxy()
            }
        }

        if RemoteControlManager.selectConfig != nil {
            resetStreamApi()
        }
    }

    @objc func healthCheckOnNetworkChange() {
        Task {
            let proxyResp = await ApiRequest.getMergedProxyData()

            var providers = Set<ClashProxyName>()

            let groups = proxyResp.proxyGroups.filter(\.type.isAutoGroup)
            for group in groups {
                group.all?.compactMap {
                    proxyResp.proxiesMap[$0]?.enclosingProvider?.name
                }.forEach {
                    providers.insert($0)
                }
            }

            for group in groups {
                Logger.log("Start auto health check for group \(group.name)")
                await ApiRequest.healthCheck(proxy: group.name)
            }

            for provider in providers {
                Logger.log("Start auto health check for provider \(provider)")
                await ApiRequest.healthCheck(proxy: provider)
            }
        }
    }
}

// MARK: Meta Core

extension AppDelegate: ClashProcessDelegate {
	
    @MainActor
    func startProxyCore() async {
        guard !ConfigManager.shared.isRunning else { return }
        await clashProcess.startIfNeeded(delegate: self)
	}
	
	func clashLaunchPathNotFound(_ msg: String) {
		let alert = NSAlert()
		alert.messageText = msg
		alert.alertStyle = .warning
		alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
		alert.runModal()

		DispatchQueue.main.async {
			NSApplication.shared.terminate(nil)
		}
	}

	func clashApiUpdated(_ server: MetaServer) {
		let port = server.externalController.components(separatedBy: ":").last ?? "9090"
		ConfigManager.shared.apiPort = port
		ConfigManager.shared.apiSecret = server.secret
		ConfigManager.shared.isRunning = true
		proxyModeMenuItem.isEnabled = true
		dashboardMenuItem.isEnabled = true
	}
	
	func clashConfigUpdated() {
		if ConfigManager.shared.restoreSystemProxy {
            Task {
                await SystemProxyManager.shared.enableProxy()
            }
		}
		
		if ConfigManager.shared.restoreTunProxy {
            Task {
                await ApiRequest.updateTun(enable: true)
                try? await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.UpdateTun(state: true, dns: ConfigManager.metaTunDNS))
            }
		} else {
            Task {
                await self.syncConfigWithTun(true)
            }
		}
		
		SSIDSuspendTool.shared.setup()
		
		resetStreamApi()
		runAfterConfigReload?()
		runAfterConfigReload = nil
		selectProxyGroupWithMemory()
        Task {
            await MenuItemFactory.recreateProxyMenuItems()
        }
		NotificationCenter.default.post(name: .reloadDashboard, object: nil)
	}
	
	func clashStartError(_ error: Error) {
		let unc = UserNotificationCenter.shared
        switch error {
        case StartMetaError.pushConfigFailed:
            ConfigManager.shared.isRunning = true
            proxyModeMenuItem.isEnabled = true
        default:
            ConfigManager.shared.isRunning = false
            proxyModeMenuItem.isEnabled = false
        }

		switch error {
		case StartMetaError.configMissing:
			unc.postConfigErrorNotice(msg: "Can't find config.")
		case StartMetaError.remoteConfigMissing:
			unc.postConfigErrorNotice(msg: "Can't find remote config.")
		case StartMetaError.helperNotFound:
			unc.postMetaErrorNotice(msg: "Can't connect to helper.")
		case StartMetaError.startMetaFailed(let s):
			unc.postMetaErrorNotice(msg: s)
		case StartMetaError.pushConfigFailed(let s):
			unc.postConfigErrorNotice(msg: s)
		default:
			unc.postMetaErrorNotice(msg: "Unknown Error.")
		}
	}
}

// MARK: Main actions

extension AppDelegate {
    @IBAction func actionDashboard(_ sender: NSMenuItem?) {
		DashboardManager.shared.show(sender)
    }

    @IBAction func actionAllowFromLan(_ sender: NSMenuItem) {
        Task {
            await updateAllowLanSetting()
        }
    }

    @IBAction func actionStartAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.shared.isEnabled = !LaunchAtLogin.shared.isEnabled
    }

    @IBAction func actionSwitchProxyMode(_ sender: NSMenuItem) {
        let mode: ClashProxyMode
        switch sender {
        case proxyModeGlobalMenuItem:
            mode = .global
        case proxyModeDirectMenuItem:
            mode = .direct
        case proxyModeRuleMenuItem:
            mode = .rule
        default:
            return
        }
        Task {
            await switchProxyMode(mode: mode)
        }
    }

    @MainActor
    func switchProxyMode(mode: ClashProxyMode) async {
        let config = ConfigManager.shared.currentConfig?.copy()
        config?.mode = mode
		_ = await ApiRequest.updateOutBoundMode(mode: mode)
		ConfigManager.shared.currentConfig = config
		ConfigManager.selectOutBoundMode = mode
		await MenuItemFactory.recreateProxyMenuItems()
    }

    @IBAction func actionShowNetSpeedIndicator(_ sender: NSMenuItem) {
        ConfigManager.shared.showNetSpeedIndicator = !(sender.state == .on)
    }

    @IBAction func actionSetSystemProxy(_ sender: Any?) {
        var canSaveProxy = true
        if ConfigManager.shared.proxyPortAutoSet && ConfigManager.shared.proxyShouldPaused.value {
            ConfigManager.shared.proxyPortAutoSet = false
        } else if ConfigManager.shared.isProxySetByOtherVariable.value {
            // should reset proxy to clashx
            ConfigManager.shared.isProxySetByOtherVariable.accept(false)
            ConfigManager.shared.proxyPortAutoSet = true
            // clear then reset.
            canSaveProxy = false
            Task {
                await SystemProxyManager.shared.disableProxy(port: 0, socksPort: 0, forceDisable: true)
            }
        } else {
            ConfigManager.shared.proxyPortAutoSet = !ConfigManager.shared.proxyPortAutoSet
        }

        if ConfigManager.shared.proxyPortAutoSet {
            if canSaveProxy {
                Task {
                    await SystemProxyManager.shared.saveProxy()
                }
            }
            Task {
                await SystemProxyManager.shared.enableProxy()
            }
        } else {
            Task {
                await SystemProxyManager.shared.disableProxy()
            }
        }
    }

    @IBAction func actionCopyExportCommand(_ sender: NSMenuItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let socksport = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        let localhost = "127.0.0.1"
        let isLocalhostCopy = sender == copyExportCommandMenuItem
        let ip = isLocalhostCopy ? localhost :
            NetworkChangeNotifier.getPrimaryIPAddress() ?? localhost
        pasteboard.setString("export https_proxy=http://\(ip):\(port) http_proxy=http://\(ip):\(port) all_proxy=socks5://\(ip):\(socksport)", forType: .string)
    }

    @IBAction func actionSpeedTest(_ sender: Any) {
		Task {
			await runSpeedTest()
        }
    }

    @IBAction func actionUpdateExternalResource(_ sender: Any) {
        Task {
            await UpdateExternalResourceAction.run()
        }
    }

    @IBAction func actionQuit(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

    @IBAction func actionMoreSetting(_ sender: Any) {
        ClashWindowController<SettingTabViewController>.create().showWindow(sender)
    }
}

// MARK: Streaming Info

extension AppDelegate: ApiRequestStreamDelegate {
	func didUpdateMemory(memory: Int64) async {
		
	}
	
	func streamStatusChanged() async {
		
	}
	
    func didUpdateTraffic(up: Int, down: Int) async {
        await MainActor.run {
            statusItemView.updateSpeedLabel(up: up, down: down)
        }
    }

        Logger.log(log, level: ClashLogLevel(rawValue: level) ?? .unknow)
    func didGetLog(log: String, level: String) async {
    }
}

// MARK: Help actions

extension AppDelegate {
    @IBAction func actionShowLog(_ sender: Any?) {
        NSWorkspace.shared.openFilePath(Logger.shared.logFilePath())
    }
}

// MARK: Config actions

extension AppDelegate {
    @IBAction func openConfigFolder(_ sender: Any) {
        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getUrl {
                url in
                if let url = url {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSWorkspace.shared.openFilePath(kConfigFolderPath)
        }
    }

    @IBAction func actionUpdateConfig(_ sender: AnyObject) {
        Task {
            _ = await updateConfig()
        }
    }

    @IBAction func actionSetLogLevel(_ sender: NSMenuItem) {
        let level = ClashLogLevel(rawValue: sender.title.lowercased()) ?? .unknow
        ConfigManager.selectLoggingApiLevel = level
        updateLoggingLevel()
        resetStreamApi()
    }

    @IBAction func actionAutoUpdateRemoteConfig(_ sender: Any) {
        RemoteConfigManager.autoUpdateEnable = !RemoteConfigManager.autoUpdateEnable
        remoteConfigAutoupdateMenuItem.state = RemoteConfigManager.autoUpdateEnable ? .on : .off
    }

    @IBAction func actionUpdateRemoteConfig(_ sender: Any) {
        Task {
            await RemoteConfigManager.shared.updateCheck(ignoreTimeLimit: true, showNotification: true)
        }
    }

    @IBAction func actionSetUpdateInterval(_ sender: Any) {
        RemoteConfigManager.showAdd()
    }

}


// MARK: Meta Menu

extension AppDelegate {
    @IBAction func actionSetTunMode(_ sender: NSMenuItem?) {
        let enable = tunModeMenuItem.state != .on
		tunModeMenuItem.isEnabled = false
        Task {
            await setTunMode(enabled: enable)
        }
    }

    @IBAction func updateGEO(_ sender: NSMenuItem) {
		guard updateGeoTimer == nil else { return }
		updateGeoTimer = Timer.scheduledTimer(withTimeInterval: 500, repeats: true) { [weak self] timer in
			
			timer.fireDate = .init(timeIntervalSinceNow: 5)
			
            Task { [weak self] in
                await self?.pollGeoUpdate(with: timer)
            }
		}
		
        Task {
            await startGeoUpdate()
        }
    }

    @IBAction func flushDNSCache(_ sender: NSMenuItem) {
        Task {
            await ApiRequest.flushDNSCache()
            try? await PrivilegedHelperManager.shared.request(ProxyConfigHelperMessages.FlushDnsCache())
        }
    }

    @IBAction func updateSniffing(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        Task {
            await setSniffing(enable: enable, sender: sender)
        }
    }
}

// MARK: crash hanlder

extension AppDelegate {
    func registCrashLogger() {
        /*
        #if DEBUG
            return
        #else
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                AppCenter.start(withAppSecret: "dce6e9a3-b6e3-4fd2-9f2d-35c767a99663", services: [
                    Analytics.self,
                    Crashes.self
                ])
            }

        #endif
         */
    }

    func failLaunchProtect() {
        #if DEBUG
            return
        #else
            UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": false])
            let x = UserDefaults.standard
            var launch_fail_times = 0
            if let xx = x.object(forKey: "launch_fail_times") as? Int { launch_fail_times = xx }
            launch_fail_times += 1
            x.set(launch_fail_times, forKey: "launch_fail_times")
            if launch_fail_times > 3 {
                // 发生连续崩溃
                ConfigFileManager.backupAndRemoveConfigFile()
				let ruleFiles = ClashResourceManager.RuleFiles.self

				try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.mmdb.rawValue)
				try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.geosite.rawValue)
				try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.geoip.rawValue)

                if let domain = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                    UserDefaults.standard.synchronize()
                }
				UserNotificationCenter.shared.post(title: "Fail on launch protect", info: "You origin Config has been renamed", notiOnly: false)
            }
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + Double(Int64(5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) {
                x.set(0, forKey: "launch_fail_times")
            }
        #endif
    }
}

// MARK: Memory

extension AppDelegate {
    func selectProxyGroupWithMemory() {
        let copy = [SavedProxyModel](ConfigManager.selectedProxyRecords)
        for item in copy {
            guard item.config == ConfigManager.selectConfigName else { continue }
            Logger.log("Auto selecting \(item.group) \(item.selected)", level: .debug)
            Task {
                await restoreSelectedProxy(item)
            }
        }
    }

    @MainActor
    func updateAllowLanSetting() async {
        let allow = !ConfigManager.allowConnectFromLan
        await ApiRequest.updateAllowLan(allow: allow)
        await syncConfig()
        ConfigManager.allowConnectFromLan = allow
    }

    @MainActor
    func runSpeedTest() async {
        if isSpeedTesting {
            UserNotificationCenter.shared.postSpeedTestingNotice()
            return
        }
        UserNotificationCenter.shared.postSpeedTestBeginNotice()
        isSpeedTesting = true

        let resp = await ApiRequest.getMergedProxyData()

        await withTaskGroup(of: Void.self) { group in
            for (name, _) in resp.enclosingProviderResp?.providers ?? [:] {
                group.addTask {
                    await ApiRequest.healthCheck(proxy: name)
                }
            }

            for p in resp.proxiesMap["GLOBAL"]?.all ?? [] {
                group.addTask {
                    _ = await ApiRequest.getProxyDelay(proxyName: p)
                }
            }
        }

        UserNotificationCenter.shared.postSpeedTestFinishNotice()
        isSpeedTesting = false
    }

    @MainActor
    func setTunMode(enabled: Bool) async {
        await ApiRequest.updateTun(enable: enabled)
        await syncConfigWithTun()
        tunModeMenuItem.state = enabled ? .on : .off
        tunModeMenuItem.isEnabled = true
    }

    @MainActor
    func setSniffing(enable: Bool, sender: NSMenuItem) async {
        await ApiRequest.updateSniffing(enable: enable)
        sender.state = enable ? .on : .off
    }

    @MainActor
    func pollGeoUpdate(with timer: Timer) async {
        let rules = await ApiRequest.getRules()
        guard updateGeoTimer != nil else { return }
        if let rule = rules.first,
           rule.payload == ClashMetaConfig.initRulePayload {
            Logger.log("Update GEO Finished.")
            _ = await updateConfig(showNotification: false)
            UserNotificationCenter.shared.post(title: "Update GEO Databases Finished.", info: "")

            timer.invalidate()
            updateGeoTimer = nil
        } else {
            timer.fireDate = .init(timeIntervalSinceNow: 0.5)
        }
    }

    @MainActor
    func startGeoUpdate() async {
        _ = await ApiRequest.updateGEO()
        UserNotificationCenter.shared.post(title: NSLocalizedString("Updating GEO Databases...", comment: ""), info: NSLocalizedString("Good luck to you  🙃", comment: ""))
        updateGeoTimer?.fire()
    }

    @MainActor
    func restoreSelectedProxy(_ item: SavedProxyModel) async {
        let success = await ApiRequest.updateProxyGroup(group: item.group, selectProxy: item.selected)
        if !success {
            ConfigManager.selectedProxyRecords.removeAll { model -> Bool in
                return model.key == item.key
            }
        }
    }

    func removeUnExistProxyGroups() {
        let action: (([String]) -> Void) = { list in
            let unexists = ConfigManager.selectedProxyRecords.filter {
                !list.contains($0.config)
            }
            ConfigManager.selectedProxyRecords.removeAll {
                unexists.contains($0)
            }
        }

        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getConfigFilesList { list in
                action(list)
            }
        } else {
            let list = ConfigManager.getConfigFilesList()
            action(list)
        }
    }

    @MainActor
    func selectOutBoundModeWithMenory() async {
        _ = await ApiRequest.updateOutBoundMode(mode: ConfigManager.selectOutBoundMode)
        await ConnectionManager.closeAllConnection()
        await syncConfig()
    }

    @MainActor
    func selectAllowLanWithMenory() async {
        await ApiRequest.updateAllowLan(allow: ConfigManager.allowConnectFromLan)
        await syncConfig()
    }

    func hasMenuSelected() -> Bool {
        if #available(macOS 11, *) {
            return statusMenu.items.contains { $0.state == .on }
        } else {
            return true
        }
    }
}

// MARK: NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard ConfigManager.shared.isRunning else { return }
		Task {
			await updateConfigFiles()
            await MenuItemFactory.refreshExistingMenuItems()
            await syncConfig()
        }
        NotificationCenter.default.post(name: .proxyMeneViewShowLeftPadding,
                                        object: nil,
                                        userInfo: ["show": hasMenuSelected()])
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        menu.items.forEach {
            ($0.view as? ProxyGroupMenuHighlightDelegate)?.highlight(item: item)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menu.items.forEach {
            ($0.view as? ProxyGroupMenuHighlightDelegate)?.highlight(item: nil)
        }
    }
}

// MARK: URL Scheme

extension AppDelegate {
    @objc func handleURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return
        }

        guard let components = URLComponents(string: url),
              let scheme = components.scheme,
              scheme.hasPrefix("clash"),
              let host = components.host
        else { return }

        if host == "install-config" {
            guard let url = components.queryItems?.first(where: { item in
                item.name == "url"
            })?.value else { return }

            var userInfo = ["url": url]
            if let name = components.queryItems?.first(where: { item in
                item.name == "name"
            })?.value {
                userInfo["name"] = name
            }

            remoteConfigAutoupdateMenuItem.menu?.performActionForItem(at: 0)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: Notification.Name(rawValue: "didGetUrl"), object: nil, userInfo: userInfo)
            }
        } else if host == "update-config" {
            Task {
                _ = await updateConfig()
            }
        }
    }
}
