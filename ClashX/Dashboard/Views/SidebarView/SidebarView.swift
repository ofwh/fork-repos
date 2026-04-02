//
//  SidebarView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct SidebarView: View {
	
	@StateObject var clashApiDatasStorage = ClashApiDatasStorage()
	
	private let timer = Timer.publish(every: 1, on: .main, in: .default).autoconnect()
	
	@State private var sidebarSelectionName: SidebarItem? = .overview
	@State private var updateConnectionsTask: Task<Void, Never>?
	
    var body: some View {
		Group {
			SidebarListView(selection: $sidebarSelectionName)
		}
		.environmentObject(clashApiDatasStorage.overviewData)
		.environmentObject(clashApiDatasStorage.logStorage)
		.environmentObject(clashApiDatasStorage.connsStorage)
		.onAppear {
			if ConfigManager.selectLoggingApiLevel == .unknow {
				ConfigManager.selectLoggingApiLevel = .info
			}
			
			clashApiDatasStorage.resetStreamApi()
			clashApiDatasStorage.connsStorage.conns.removeAll()
			
			updateConnections()
		}
		.onChange(of: sidebarSelectionName) { newValue in
			sidebarItemChanged(newValue)
		}
		.onReceive(timer, perform: { _ in
			updateConnections()
		})
		.onDisappear {
			updateConnectionsTask?.cancel()
			updateConnectionsTask = nil
		}

	}
	
	@MainActor
	func updateConnections() {
		let previousTask = updateConnectionsTask
		updateConnectionsTask = Task {
			await previousTask?.value
			guard !Task.isCancelled,
				  let snap = await ApiRequest.getConnectionsSnapshot(),
				  !Task.isCancelled else { return }
			await applyConnectionsSnapshot(snap)
		}
	}

	@MainActor
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
