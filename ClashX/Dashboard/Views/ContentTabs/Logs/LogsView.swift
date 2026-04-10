//
//  LogsView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct LogsView: View {
	
	@EnvironmentObject var logStorage: ClashLogStorage
	
	@State var searchString: String = ""
    @State var logFilter = DashboardViewContoller.LogFilter.all
    
	@State var logLevel = ConfigManager.selectLoggingApiLevel
	
    var body: some View {
		Group {
			LogsTableView(
                data: logStorage.logs.reversed(),
                filterString: searchString,
                logFilter: logFilter
            )
		}
		.onAppear {
			guard let s = ToolbarStore.shared.searchStrings["logs"] else { return }
			searchString = s
			NotificationCenter.default.post(name: .initSearchString, object: nil, userInfo: ["string": s])
		}
		.onDisappear {
			ToolbarStore.shared.searchStrings["logs"] = searchString
		}
		.onReceive(NotificationCenter.default.publisher(for: .toolbarSearchString)) {
			guard let string = $0.userInfo?["String"] as? String else { return }
			searchString = string
		}
		.onReceive(NotificationCenter.default.publisher(for: .logLevelChanged)) {
			guard let level = $0.userInfo?["level"] as? ClashLogLevel else { return }
			logLevelChanged(level)
		}
        .onReceive(NotificationCenter.default.publisher(for: .logFilterChanged)) {
            guard let level = $0.userInfo?["filter"] as? DashboardViewContoller.LogFilter else { return }
            logFilterChanged(level)
        }
    }
	
	func logLevelChanged(_ level: ClashLogLevel) {
		logStorage.logs.removeAll()
		ConfigManager.selectLoggingApiLevel = level
		ApiRequest.shared.resetStreamApi(for: .logging)
	}
    
    func logFilterChanged(_ filter: DashboardViewContoller.LogFilter) {
        logFilter = filter
    }
}

struct LogsView_Previews: PreviewProvider {
    static var previews: some View {
        LogsView()
    }
}
