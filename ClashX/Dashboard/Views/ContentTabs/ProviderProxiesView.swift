//
//  ProviderProxiesView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProviderProxiesView: View {
	
	@ObservedObject var provider: DBProxyProvider
	@EnvironmentObject var hideProxyNames: HideProxyNames
	@EnvironmentObject var searchString: ProxiesSearchString
	
	@State private var columnCount: Int = 3
	@State private var isTesting = false
	@State private var isUpdating = false
	
	var proxies: [DBProxy] {
		if searchString.string.isEmpty {
			return provider.proxies
		} else {
			return provider.proxies.filter {
				$0.name.lowercased().contains(searchString.string.lowercased())
			}
		}
	}
	
    var body: some View {
		ZStack {
			ScrollView {
				Section {
					proxyListView
				} header: {
					HStack {
						ProxyProviderInfoView(provider: provider)
						buttonsView
					}
				}
				.padding()
			}
			GeometryReader { geometry in
				Rectangle()
					.fill(.clear)
					.frame(height: 1)
					.onChange(of: geometry.size.width) { newValue in
						updateColumnCount(newValue)
					}
					.onAppear {
						updateColumnCount(geometry.size.width)
					}
			}
			.frame(height: 1)
			.padding()
		}
    }
	
	func updateColumnCount(_ width: Double) {
		let v = Int(Int(width) / 180)
		let new = v == 0 ? 1 : v
		
		if new != columnCount {
			columnCount = new
		}
	}
	
	var proxyListView: some View {
		LazyVGrid(columns: Array(repeating: GridItem(.flexible()),
								 count: columnCount)) {
			ForEach(proxies, id: \.id) { proxy in
				ProxyNodeView(
					proxy: proxy,
					selectable: false
				)
				.background(Color(compatible: .textBackgroundColor))
				.cornerRadius(8)
			}
		}
	}
	
	var buttonsView: some View {
		VStack {
					ProgressButton(
						title: "Health Check",
						title2: "Testing",
						iconName: "bolt.fill",
						inProgress: $isTesting,
						autoWidth: false) {
					Task {
						await startHealthCheck()
					}
				}
			
					ProgressButton(
						title: "Update",
						title2: "Updating",
						iconName: "arrow.clockwise",
						inProgress: $isUpdating,
						autoWidth: false) {
					Task {
						await startUpdate()
					}
				}
		}
		.frame(width: ProgressButton.width(
			[
			"Health Check",
			"Testing",
			"Update",
			"Updating"]
		))
	}
	
	@MainActor
	func startHealthCheck() async {
		isTesting = true
		await ProxyHealthCheckManager.shared.healthCheck(proxy: provider.name)
		await updateProvider()
		isTesting = false
	}
	
	@MainActor
	func startUpdate() async {
		isUpdating = true
		_ = await ApiRequest.updateProvider(for: .proxy, name: provider.name)
		await updateProvider()
		isUpdating = false
	}
	
	@MainActor
	func updateProvider() async {
		let resp = await ApiRequest.requestProxyProviderList()
		if let p = resp.allProviders[provider.name] {
			provider.updateInfo(DBProxyProvider(provider: p))
		}
	}
}

//struct ProviderProxiesView_Previews: PreviewProvider {
//    static var previews: some View {
//        ProviderProxiesView()
//    }
//}
