//
//  ConnectionsView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ConnectionsView: View {
	
	@EnvironmentObject var data: ClashConnsStorage
	
	@State private var searchString: String = ""
	
    var body: some View {

		ConnectionsTableView(data: data.conns,
							 filterString: searchString)
		.background(Color(compatible: .textBackgroundColor))
			.onAppear {
				guard let s = ToolbarStore.shared.searchStrings["conns"] else { return }
				searchString = s
				NotificationCenter.default.post(name: .initSearchString, object: nil, userInfo: ["string": s])
			}
			.onDisappear {
				ToolbarStore.shared.searchStrings["conns"] = searchString
			}
			.onReceive(NotificationCenter.default.publisher(for: .toolbarSearchString)) {
				guard let string = $0.userInfo?["String"] as? String else { return }
				searchString = string
			}
			.onReceive(NotificationCenter.default.publisher(for: .stopConns)) { _ in
				stopConns()
			}
	}
	
	func stopConns() {
		Task {
			await ApiRequest.closeAllConnection()
		}
	}
}

struct ConnectionsView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionsView()
    }
}
