//
//  ProvidersView.swift
//  ClashX Dashboard
//
//

import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

struct ProvidersView: View {
	@ObservedObject var providerStorage = DBProviderStorage()
	
	@State private var searchString = ProxiesSearchString()
	
	@StateObject private var hideProxyNames = HideProxyNames()
	
    var body: some View {
		NavigationView {
			listView
			EmptyView()
		}
        .background(Color("SwiftUI Colors/WindowBackgroundColor"))
		.onReceive(NotificationCenter.default.publisher(for: .toolbarSearchString)) {
			guard let string = $0.userInfo?["String"] as? String else { return }
			searchString.string = string
		}
		.onReceive(NotificationCenter.default.publisher(for: .hideNames)) {
			guard let hide = $0.userInfo?["hide"] as? Bool else { return }
			hideProxyNames.hide = hide
		}
		.environmentObject(searchString)
		.task {
			await loadProviders()
		}
		.environmentObject(hideProxyNames)
    }
	
	var listView: some View {
		List {
            let httpProxyProviders = providerStorage.proxyProviders.filter({ $0.vehicleType == .HTTP })
            let inlineProxyProviders = providerStorage.proxyProviders.filter({ $0.vehicleType == .Inline })
            
            let httpRuleProviders = providerStorage.ruleProviders.filter({ $0.vehicleType == .HTTP })
            let inlineRuleProviders = providerStorage.ruleProviders.filter({ $0.vehicleType == .Inline })
            
            if httpProxyProviders.isEmpty,
               httpRuleProviders.isEmpty,
               inlineRuleProviders.isEmpty {
				Text("Empty")
					.padding()
			} else {
				Section() {
					if !httpProxyProviders.isEmpty {
						ProxyProvidersRowView(providerStorage: providerStorage)
					}
					if !httpRuleProviders.isEmpty {
                        RuleProvidersRowView(providerStorage: providerStorage, vehicleType: .HTTP)
					}
                    if !inlineRuleProviders.isEmpty {
                        RuleProvidersRowView(providerStorage: providerStorage, vehicleType: .Inline)
                    }
				} header: {
					Text("Providers")
				}
			}
			
            if httpProxyProviders.count > 0 {
				Text("")
				Section() {
					ForEach(httpProxyProviders,id: \.id) {
						ProviderRowView(proxyProvider: $0)
					}
				} header: {
					Text("Proxy Provider")
				}
			}
            
            if inlineProxyProviders.count > 0 {
                Text("")
                Section() {
                    ForEach(inlineProxyProviders,id: \.id) {
                        ProviderRowView(proxyProvider: $0)
                    }
                } header: {
                    Text("Proxy Provider Inline")
                }
            }
		}
		.introspect(.table, on: .macOS(.v12...)) {
			$0.refusesFirstResponder = true
			$0.doubleAction = nil
		}
		.listStyle(.plain)
	}
	
	@MainActor
	func loadProviders() async {
		let proxyResp = await ApiRequest.requestProxyProviderList()
		providerStorage.proxyProviders = proxyResp.allProviders.values.sorted {
			$0.name < $1.name
		}
		.map(DBProxyProvider.init)

		let ruleResp = await ApiRequest.requestRuleProviderList()
            providerStorage.ruleProviders = ruleResp.allProviders.values.sorted {
                $0.name < $1.name
            }
            .map(DBRuleProvider.init)
	}
	
}

//struct ProvidersView_Previews: PreviewProvider {
//    static var previews: some View {
//        ProvidersView()
//    }
//}
