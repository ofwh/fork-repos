//
//  RulesView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct RulesView: View {
	
	@State var ruleItems = [ClashRule]()
	
	@State private var searchString: String = ""
	
	
	var rules: [EnumeratedSequence<[ClashRule]>.Element] {
		if searchString.isEmpty {
			return Array(ruleItems.enumerated())
		} else {
			return Array(ruleItems.filtered(searchString, for: ["type", "payload", "proxy"]).enumerated())
		}
	}
	
	
    var body: some View {
		List {
			ForEach(rules, id: \.element.id) {
				RuleItemView(index: $0.offset, rule: $0.element)
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: .toolbarSearchString)) {
			guard let string = $0.userInfo?["String"] as? String else { return }
			searchString = string
		}
		.task {
			await loadRules()
		}
    }

	@MainActor
	func loadRules() async {
		ruleItems.removeAll()

		let resp = await ApiRequest.requestRuleProviderList()
		let ruleProviders = resp.allProviders.values.sorted {
				$0.name < $1.name
			}
			.map(DBRuleProvider.init)

		var items = await ApiRequest.getRules()
		items.enumerated().forEach {
			guard let payload = $0.element.payload,
				  let pd = ruleProviders.first(where: { $0.name == payload }) else { return }

			items[$0.offset].size = pd.ruleCount
		}

		ruleItems = items
	}
}

//struct RulesView_Previews: PreviewProvider {
//    static var previews: some View {
//        RulesView()
//    }
//}
