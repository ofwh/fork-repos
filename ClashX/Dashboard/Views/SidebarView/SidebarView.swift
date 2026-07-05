//
//  SidebarView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct SidebarView: View {
	
	@StateObject var clashApiDatasStorage = ClashApiDatasStorage()
	
	@State private var sidebarSelectionName: SidebarItem? = .overview
	@State private var updateConnectionsTask: Task<Void, Never>?
	@State private var pollingTask: Task<Void, Never>?
	
    var body: some View {
		Group {
			SidebarListView(selection: $sidebarSelectionName)
		}
		.environmentObject(clashApiDatasStorage.overviewData)
		.environmentObject(clashApiDatasStorage.logStorage)
		.environmentObject(clashApiDatasStorage.connsStorage)
		.onAppear {
			if ConfigOverride.shared.logLevel == .unknow {
				ConfigOverride.shared.logLevel = .info
			}
			
			clashApiDatasStorage.resetStreamApi()
			clashApiDatasStorage.connsStorage.conns.removeAll()
			
			updateConnections()
			startPollingConnections()
		}
		.onChange(of: sidebarSelectionName) { newValue in
			sidebarItemChanged(newValue)
		}
		.onDisappear {
			pollingTask?.cancel()
			pollingTask = nil
			updateConnectionsTask?.cancel()
			updateConnectionsTask = nil
		}

	}

	func startPollingConnections() {
		pollingTask?.cancel()
		pollingTask = Task {
			while !Task.isCancelled {
				try? await Task.sleep(seconds: 1)
				guard !Task.isCancelled else { return }
				updateConnections()
			}
		}
	}
	
	func updateConnections() {
		let previousTask = updateConnectionsTask
		updateConnectionsTask = Task {
			await previousTask?.value
			guard !Task.isCancelled,
				  let snap = await ApiRequest.getConnectionsSnapshot(),
				  !Task.isCancelled else { return }
			applyConnectionsSnapshot(snap)
		}
	}

	func applyConnectionsSnapshot(_ snap: DBConnectionSnapShot) {
		clashApiDatasStorage.overviewData.upTotal = snap.uploadTotal
		clashApiDatasStorage.overviewData.downTotal = snap.downloadTotal
		clashApiDatasStorage.overviewData.activeConns = "\(snap.connections.count)"
		clashApiDatasStorage.connsStorage.conns = snap.connections
	}
	
	func sidebarItemChanged(_ item: SidebarItem?) {
		guard let item else { return }
		
		NotificationCenter.default.post(name: .sidebarItemChanged, object: nil, userInfo: ["item": item])
	}
}

//struct SidebarView_Previews: PreviewProvider {
//    static var previews: some View {
//		SidebarView()
//    }
//}
