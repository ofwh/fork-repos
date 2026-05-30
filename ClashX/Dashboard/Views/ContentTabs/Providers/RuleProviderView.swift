//
//  RuleProviderView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct RuleProviderView: View {
	
	@State var provider: DBRuleProvider
	
    var body: some View {
        
		VStack(alignment: .leading) {
			HStack {
				Text(provider.name)
					.font(.title2)
					.fontWeight(.medium)
				Text(provider.type)
				Text(provider.behavior)
				Spacer()
			}
			
			HStack {
				Text(String(format: NSLocalizedString("%lld rules", comment: ""), provider.ruleCount))
				Text(String(format: NSLocalizedString("Updated %@", comment: ""), RelativeDateTimeFormatter().localizedString(for: provider.updatedAt, relativeTo: Date())))
				Spacer()
			}
			.font(.system(size: 12))
			.foregroundColor(.secondary)
		}
    }
}

//struct RuleProviderView_Previews: PreviewProvider {
//    static var previews: some View {
//        RuleProviderView()
//    }
//}
