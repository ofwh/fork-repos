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

	func loadRules() async {
		async let providerResponse = ApiRequest.requestRuleProviderList()
		async let rulesResponse = ApiRequest.getRules()

		let providerRuleCounts = await providerResponse.allProviders.values.reduce(into: [ClashProviderName: Int]()) {
			$0[$1.name] = $1.ruleCount
		}
		var items = await rulesResponse

		items.indices.forEach { index in
			guard let payload = items[index].payload,
				  let ruleCount = providerRuleCounts[payload] else { return }
			items[index].size = ruleCount
		}

		guard !Task.isCancelled else { return }
        ruleItems = items
	}
}

//struct RulesView_Previews: PreviewProvider {
//    static var previews: some View {
//        RulesView()
//    }
//}
