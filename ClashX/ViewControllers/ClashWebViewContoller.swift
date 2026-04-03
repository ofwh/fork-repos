//
//  ClashWebViewContoller.swift
//  ClashX
//
//  Created by yicheng on 2018/8/28.
//  Copyright © 2018年 west2online. All rights reserved.
//

import Cocoa
import RxCocoa
import RxSwift
import WebKit

enum WebCacheCleaner {
    @MainActor
    static func clean() async {
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        Logger.log("[WebCacheCleaner] All cookies deleted")
		
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(ofTypes: types, for: records)
        Logger.log("[WebCacheCleaner] All records deleted")
    }
}

class ClashWebViewWindowController: NSWindowController {
    var onWindowClose: (() -> Void)?

    static func create() -> ClashWebViewWindowController {
        let win = NSWindow()
        win.center()
        let wc = ClashWebViewWindowController(window: win)
        wc.contentViewController = ClashWebViewContoller()
        return wc
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(self)
        window?.delegate = self
    }
}

extension ClashWebViewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onWindowClose?()
        if let contentVC = contentViewController as? ClashWebViewContoller, let win = window {
            if !win.styleMask.contains(.fullScreen) {
                contentVC.lastSize = win.frame.size
            }
        }
    }
}

class ClashWebViewContoller: NSViewController {
    let webview: CustomWKWebView = .init()
    let disposeBag = DisposeBag()
    let minSize = NSSize(width: 920, height: 580)
    var lastSize: CGSize? {
        get {
            if let str = UserDefaults.standard.value(forKey: "ClashWebViewContoller.lastSize") as? String {
                return NSSizeFromString(str) as CGSize
            }
            return nil
        }
        set {
            if let size = newValue {
                UserDefaults.standard.set(NSStringFromSize(size), forKey: "ClashWebViewContoller.lastSize")
            }
        }
    }

    let effectView = NSVisualEffectView()

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: minSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        webview.uiDelegate = self
        webview.navigationDelegate = self

        webview.customUserAgent = "ClashX Runtime"
#if DEBUG
        if #available(macOS 13.3, *) {
            webview.isInspectable = true
        }
#endif
        webview.setValue(false, forKey: "drawsBackground")
        let script = WKUserScript(source: "console.log(\"dashboard loaded\")", injectionTime: .atDocumentStart, forMainFrameOnly: false)

        webview.configuration.userContentController.addUserScript(script)

        webview.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        NotificationCenter.default.rx.notification(.configFileChange).bind {
            [weak self] _ in
			self?.webview.reload()
        }.disposed(by: disposeBag)

        NotificationCenter.default.rx.notification(.reloadDashboard).bind {
            [weak self] _ in
            self?.webview.reload()
        }.disposed(by: disposeBag)

        loadWebRecourses()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.titleVisibility = .hidden
        view.window?.titlebarAppearsTransparent = false
        view.window?.styleMask.insert(.fullSizeContentView)

        view.window?.isOpaque = false
        view.window?.backgroundColor = NSColor.clear
		view.window?.styleMask.insert(.closable)
		view.window?.styleMask.insert(.resizable)
		view.window?.styleMask.insert(.miniaturizable)
        view.wantsLayer = true
        view.layer?.cornerRadius = 10

        view.window?.minSize = minSize
        if let lastSize = lastSize, lastSize != .zero {
            view.window?.setContentSize(lastSize)
        }
        view.window?.center()
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func setupView() {
        view.addSubview(effectView)
        view.addSubview(webview)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        effectView.frame = view.bounds
        webview.frame = view.bounds
    }

    func loadWebRecourses() {
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeMemoryCache], modifiedSince: Date(timeIntervalSince1970: 0), completionHandler: {})
        // defaults write com.west2online.ClashX webviewUrl "your url"
        var defaultUrl = "http://127.0.0.1:\(ConfigManager.shared.apiPort)/ui/"

        var params = [String]()
        let cm = ConfigManager.shared
		
		params.append("hostname=127.0.0.1")
		params.append("port=\(cm.apiPort)")
		
        if cm.apiSecret != "" {
            params.append("secret=\(cm.apiSecret)")
        }
        if params.count > 0 {
            defaultUrl += "?"
            defaultUrl += params.joined(separator: "&")
        }

        let url = UserDefaults.standard.string(forKey: "webviewUrl") ?? defaultUrl
        if let url = URL(string: url) {
            webview.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 0))
            return
        }
		
        if let url = URL(string: defaultUrl) {
            Logger.log("dashboard url:\(defaultUrl)")
            webview.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 0))
            return
        }
        Logger.log("load dashboard url fail", level: .error)
    }

    deinit {
        NSApp.setActivationPolicy(.accessory)
    }
}


extension ClashWebViewContoller: WKUIDelegate, WKNavigationDelegate {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.log("[dashboard] webview crashed", level: .error)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Logger.log("[dashboard] load request \(String(describing: navigationAction.request.url?.absoluteString))", level: .debug)
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.log("[dashboard] didFinish \(String(describing: navigation))", level: .info)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.log("[dashboard] \(String(describing: navigation)) error: \(error)", level: .error)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

class CustomWKWebView: WKWebView {
    var dragableAreaHeight: CGFloat = 30
    let alwaysDragableLeftAreaWidth: CGFloat = 150

    private func isInDargArea(with event: NSEvent?) -> Bool {
        guard let event = event else { return false }
        let x = event.locationInWindow.x
        let y = (window?.frame.size.height ?? 0) - event.locationInWindow.y
        return x < alwaysDragableLeftAreaWidth || y < dragableAreaHeight
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        if isInDargArea(with: event) {
            return true
        }
        return super.acceptsFirstMouse(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if isInDargArea(with: event) {
            window?.performDrag(with: event)
        }
    }
}
