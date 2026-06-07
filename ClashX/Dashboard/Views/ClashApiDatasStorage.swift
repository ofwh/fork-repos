//
//  ClashApiDatasStorage.swift
//  ClashX Dashboard
//
//

import Cocoa
import SwiftUI
import CocoaLumberjackSwift

@MainActor
class ClashApiDatasStorage: NSObject, ObservableObject {
	private static let memoryFormatter = ByteCountFormatter()
	
	@Published var overviewData = ClashOverviewData()
	
	@Published var logStorage = ClashLogStorage()
	@Published var connsStorage = ClashConnsStorage()

	private var pendingTraffic: (up: Int, down: Int)?
	private var pendingLogs = [(level: String, log: String)]()
	private var pendingMemory: String?
	private var uiUpdateTask: Task<Void, Never>?

	override init() {
		super.init()
		uiUpdateTask = Task { [weak self] in
			while !Task.isCancelled {
				try? await Task.sleep(seconds: 1)
				guard let self else { return }
                flushPendingUpdates()
			}
		}
	}

	deinit {
		uiUpdateTask?.cancel()
	}
	
	func resetStreamApi() {
		ApiRequest.shared.dashboardDelegate = self
		if ApiRequest.shared.delegate == nil {
			ApiRequest.shared.resetStreamApis()
		}
	}
}

extension ClashApiDatasStorage: ApiRequestStreamDelegate {
    func streamStatusChanged() async {
    }

	func didUpdateTraffic(up: Int, down: Int) async {
        enqueueTrafficUpdate(up: up, down: down)
	}
	
	func didGetLog(log: String, level: String) async {
        enqueueLog(level: level, log: log)
	}
	
	func didUpdateMemory(memory: Int64) async {
        let memoryString = Self.memoryFormatter.string(fromByteCount: memory)
        enqueueMemory(memoryString)
	}

	func enqueueTrafficUpdate(up: Int, down: Int) {
		pendingTraffic = (up: up, down: down)
	}

	func enqueueLog(level: String, log: String) {
		pendingLogs.append((level: level, log: log))
	}

	func enqueueMemory(_ value: String) {
		pendingMemory = value
	}

	func flushPendingUpdates() {
		if let traffic = pendingTraffic {
			overviewData.down = traffic.down
			overviewData.up = traffic.up
			pendingTraffic = nil
		}

		if !pendingLogs.isEmpty {
			logStorage.logs.append(contentsOf: pendingLogs.map { .init(level: $0.level, log: $0.log) })
			pendingLogs.removeAll(keepingCapacity: true)

			if logStorage.logs.count > 1000 {
				logStorage.logs.removeFirst(100)
			}
		}

		if let memory = pendingMemory {
			if overviewData.memory != memory {
				overviewData.memory = memory
			}
			pendingMemory = nil
		}
	}
	
}

fileprivate let TrafficHistoryLimit = 120

class ClashOverviewData: ObservableObject, Identifiable {
	let id = UUID().uuidString
	
	@Published var uploadString = "N/A"
	@Published var downloadString = "N/A"
	
	@Published var downloadTotal = "N/A"
	@Published var uploadTotal = "N/A"
	
	@Published var activeConns = "0"
	
	@Published var memory = "0 MB"
	
	@Published var downloadHistories = [CGFloat](repeating: 0, count: TrafficHistoryLimit)
	@Published var uploadHistories = [CGFloat](repeating: 0, count: TrafficHistoryLimit)
	
	var down: Int = 0 {
		didSet {
			downloadString = getSpeedString(for: down)
			downloadHistories.append(CGFloat(down))
			
			if downloadHistories.count > TrafficHistoryLimit {
				downloadHistories.removeFirst()
			}
		}
	}
	
	var up: Int = 0 {
		didSet {
			uploadString = getSpeedString(for: up)
			uploadHistories.append(CGFloat(up))
			
			if uploadHistories.count > TrafficHistoryLimit {
				uploadHistories.removeFirst()
			}
		}
	}
	
	var downTotal: Int = 0 {
		didSet {
			downloadTotal = getSpeedString(for: downTotal).replacingOccurrences(of: "/s", with: "")
		}
	}
	
	var upTotal: Int = 0 {
		didSet {
			uploadTotal = getSpeedString(for: upTotal).replacingOccurrences(of: "/s", with: "")
		}
	}
	
	func getSpeedString(for byte: Int) -> String {
		let kb = byte / 1000
		if kb < 1000 {
			return  "\(kb)KB/s"
		} else {
			let mb = Double(kb) / 1000
			if mb >= 100 {
				if mb >= 1000 {
					return String(format: "%.1fGB/s", mb/1000)
				}
				return String(format: "%.1fMB/s", mb)
			} else {
				return String(format: "%.2fMB/s", mb)
			}
		}
	}
}

class ClashLogStorage: ObservableObject {
	@Published var logs = [ClashLog]()
	
	class ClashLog: NSObject, ObservableObject {
		let id: String
		
		let date: Date
		let level: ClashLogLevel
		@objc let log: String
		
		let levelColor: NSColor
		@objc let levelString: String
		
		init(level: String, log: String) {
			id = UUID().uuidString
			date = Date()
			
			self.level = .init(rawValue: level) ?? .unknow
			self.log = log
			
			self.levelString = level
			switch self.level {
			case .info:
				levelColor = .systemBlue
			case .warning:
				levelColor = .systemYellow
			case .error:
				levelColor = .systemRed
			case .debug:
				levelColor = .systemGreen
			default:
				levelColor = .white
			}
		}
	}
}

class ClashConnsStorage: ObservableObject {
	@Published var conns = [DBConnection]()
}
