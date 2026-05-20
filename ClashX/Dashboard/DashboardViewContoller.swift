//
//  DashboardViewContoller.swift
//  ClashX
//
//  Created by yicheng on 2018/8/28.
//  Copyright © 2018年 west2online. All rights reserved.
//

import Cocoa
import SwiftUI

public class DashboardWindowController: NSWindowController {
    private static let storyboardName = NSStoryboard.Name("Dashboard")

    public var onWindowClose: (() -> Void)?

	public static func create() -> DashboardWindowController {
		let controller = NSStoryboard(name: storyboardName, bundle: Bundle.main)
			.instantiateInitialController()

		guard let controller = controller as? DashboardWindowController else {
			fatalError("Failed to instantiate DashboardWindowController from Dashboard.storyboard")
		}

		return controller
    }

	public override func windowDidLoad() {
		super.windowDidLoad()

		guard let window else { return }
		window.delegate = self
		window.styleMask.insert(.fullSizeContentView)
		window.isOpaque = false
		window.title = "Dashboard"
	}

	public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(self)
    }
	
	public func set(_ apiURL: String, secret: String? = nil) {
		ConfigManager.shared.overrideApiURL = .init(string: apiURL)
		ConfigManager.shared.overrideSecret = secret
	}
}

extension DashboardWindowController: NSWindowDelegate {
	public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onWindowClose?()
    }
}

class DashboardViewContoller: NSViewController {
	private let levels = [
		ClashLogLevel.silent,
		.error,
		.warning,
		.info,
		.debug
	]
    
    enum LogFilter: String, CaseIterable {
        case all = "All"
        case rule = "Rule"
        case dns = "DNS"
        case others = "Others"
    }
	
	private var sidebarItemObserver: NSObjectProtocol?
	private var searchStringObserver: NSObjectProtocol?

	override func loadView() {
		view = NSHostingView(rootView: DashboardView())
    }

	override func viewDidLoad() {
        super.viewDidLoad()
		
		sidebarItemObserver = NotificationCenter.default.addObserver(forName: .sidebarItemChanged, object: nil, queue: .main) {
			guard let item = $0.userInfo?["item"] as? SidebarItem else { return }
			
			var items = [NSToolbarItem.Identifier]()
			items.append(.toggleSidebar)
            items.append(.sidebarTrackingSeparator)
			
			switch item {
			case .overview, .config:
				break
			case .proxies, .providers:
				items.append(.hideNamesItem)
				items.append(.searchItem)
			case .rules:
				items.append(.searchItem)
			case .conns:
				items.append(.stopConnsItem)
				items.append(.searchItem)
			case .logs:
                items.append(.logFilterItem)
				items.append(.logLevelItem)
				items.append(.searchItem)
			}
			self.reinitToolbar(items)
		}
		
		searchStringObserver = NotificationCenter.default.addObserver(forName: .initSearchString, object: nil, queue: .main) {
			guard let str = $0.userInfo?["string"] as? String,
				  let toolbar = self.view.window?.toolbar,
				  let searchItem = toolbar.items.first(where: { $0.itemIdentifier == .searchItem }) as? NSSearchToolbarItem else { return }
			
			searchItem.searchField.stringValue = str
		}
    }

	public override func viewWillAppear() {
		super.viewWillAppear()
		guard view.window?.toolbar == nil else { return }
		
		let toolbar = NSToolbar(identifier: .init("DashboardToolbar"))
		toolbar.displayMode = .iconOnly
		toolbar.delegate = self
		
		view.window?.toolbar = toolbar
		reinitToolbar([])

		if NSApp.activationPolicy() == .accessory {
			NSApp.setActivationPolicy(.regular)
		}
	}
	
	func reinitToolbar(_ items: [NSToolbarItem.Identifier]) {
		guard let toolbar = view.window?.toolbar else { return }
		
		toolbar.items.enumerated().reversed().forEach {
			toolbar.removeItem(at: $0.offset)
		}
		
		items.reversed().forEach {
			toolbar.insertItem(withItemIdentifier: $0, at: 0)
		}
	}

    deinit {
		if let sidebarItemObserver {
			NotificationCenter.default.removeObserver(sidebarItemObserver)
		}
		if let searchStringObserver {
			NotificationCenter.default.removeObserver(searchStringObserver)
		}
        NSApp.setActivationPolicy(.accessory)
    }
}


extension NSToolbarItem.Identifier {
	static let hideNamesItem = NSToolbarItem.Identifier("HideNamesItem")
	static let stopConnsItem = NSToolbarItem.Identifier("StopConnsItem")
	static let logLevelItem = NSToolbarItem.Identifier("LogLevelItem")
    static let logFilterItem = NSToolbarItem.Identifier("logFilterItem")
	static let searchItem = NSToolbarItem.Identifier("SearchItem")
}

extension DashboardViewContoller: NSSearchFieldDelegate {
	
	func controlTextDidChange(_ obj: Notification) {
		guard let obj = obj.object as? NSSearchField else { return }
		let str = obj.stringValue
		NotificationCenter.default.post(name: .toolbarSearchString, object: nil, userInfo: ["String": str])
	}
	
	@IBAction func stopConns(_ sender: NSToolbarItem) {
		NotificationCenter.default.post(name: .stopConns, object: nil)
	}
	
	@IBAction func hideNames(_ sender: NSToolbarItem) {
		switch sender.tag {
		case 0:
			sender.tag = 1
			sender.image = NSImage(systemSymbolName: "eyeglasses", accessibilityDescription: nil)
		case 1:
			sender.tag = 0
			sender.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
		default:
			break
		}
		
		NotificationCenter.default.post(name: .hideNames, object: nil, userInfo: ["hide": sender.tag == 1])
	}
	
	@objc func setLogLevel(_ sender: NSToolbarItemGroup) {
		guard sender.selectedIndex < levels.count, sender.selectedIndex >= 0 else { return }
		let level = levels[sender.selectedIndex]
		
		NotificationCenter.default.post(name: .logLevelChanged, object: nil, userInfo: ["level": level])
	}
	
    
    @objc func setLogFilter(_ sender: NSToolbarItemGroup) {
        guard sender.selectedIndex < LogFilter.allCases.count, sender.selectedIndex >= 0 else { return }
        let filter = LogFilter.allCases[sender.selectedIndex]
        
        NotificationCenter.default.post(name: .logFilterChanged, object: nil, userInfo: ["filter": filter])
    }
    
}

	extension DashboardViewContoller: NSToolbarDelegate, NSToolbarItemValidation {
	
		func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
			return true
		}
	
	func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		
		switch itemIdentifier {
		case .searchItem:
			let item = NSSearchToolbarItem(itemIdentifier: .searchItem)
			item.resignsFirstResponderWithCancel = true
			item.searchField.delegate = self
			item.toolTip = "Search"
			return item
		case .toggleSidebar:
			return NSTrackingSeparatorToolbarItem(itemIdentifier: .toggleSidebar)
		case .logLevelItem:

			let titles = levels.map {
				$0.rawValue.capitalized
			}
			
			let group = NSToolbarItemGroup(itemIdentifier: .logLevelItem, titles: titles, selectionMode: .selectOne, labels: titles, target: nil, action: #selector(setLogLevel(_:)))
			group.selectionMode = .selectOne
			group.controlRepresentation = .collapsed
			group.selectedIndex = levels.firstIndex(of: ConfigManager.selectLoggingApiLevel) ?? 0
			
            group.label = "Log Level"
            
			return group
        case .logFilterItem:
            let titles = LogFilter.allCases.map {
                $0.rawValue
            }
            
            let group = NSToolbarItemGroup(itemIdentifier: .logFilterItem, titles: titles, selectionMode: .selectOne, labels: titles, target: nil, action: #selector(setLogFilter(_:)))
            
            group.selectionMode = .selectOne
            group.controlRepresentation = .collapsed
            group.selectedIndex = 0
            
            group.label = "Log Filter"
            
            return group
		case .hideNamesItem:
			let item = NSToolbarItem(itemIdentifier: .hideNamesItem)
			item.target = self
			item.action = #selector(hideNames(_:))
			item.isBordered = true
			item.tag = 0
			item.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
            
            item.label = "Hide Names"
            
			return item
		case .stopConnsItem:
			let item = NSToolbarItem(itemIdentifier: .stopConnsItem)
			item.target = self
			item.action = #selector(stopConns(_:))
			item.isBordered = true
			item.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
            
            item.label = "Stop All"
            
			return item
		default:
			break
		}
		
		return nil
	}
	
	
	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[
			.toggleSidebar,
			.stopConnsItem,
			.hideNamesItem,
			.logLevelItem,
            .logFilterItem,
			.searchItem
		]
	}
	
	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		[
			.toggleSidebar,
			.stopConnsItem,
			.hideNamesItem,
			.logLevelItem,
            .logFilterItem,
			.searchItem
		]
	}
}
