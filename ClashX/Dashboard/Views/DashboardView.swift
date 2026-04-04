//
//  DashboardView.swift
//  ClashX Dashboard
//
//

import SwiftUI

class HideProxyNames: ObservableObject, Identifiable {
	let id = UUID().uuidString
	@Published var hide = false
}

struct DashboardView: View {
	static let minimumSize = CGSize(width: 920, height: 580)
	
	private let runningState = NotificationCenter.default.publisher(for: .init("ClashRunningStateChanged"))
	@State private var isRunning = false
	
	var body: some View {
		NavigationView {
			SidebarView()
			EmptyView()
		}
		.frame(
			minWidth: Self.minimumSize.width,
			idealWidth: Self.minimumSize.width,
			minHeight: Self.minimumSize.height,
			idealHeight: Self.minimumSize.height
		)
		.onReceive(runningState) { _ in
			isRunning = ConfigManager.shared.isRunning
		}
		
	}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
		DashboardView()
    }
}
