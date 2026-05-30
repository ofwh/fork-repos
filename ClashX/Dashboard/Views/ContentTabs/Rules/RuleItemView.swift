//
//  RuleItemView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct RuleItemView: View {
	@State var index: Int
	@State var rule: ClashRule

    var body: some View {
		HStack(alignment: .center, spacing: 12) {
			Text("\(index)")
				.font(.system(size: 16))
				.foregroundColor(.secondary)
				.frame(width: 30)
			
			VStack(alignment: .leading) {
				HStack(alignment: .bottom, spacing: 18) {
					if let payload = rule.payload,
					   payload != "" {
						Text(rule.payload!)
							.font(.system(size: 14))
					}
				}
				
				
				HStack {
					HStack(alignment: .bottom, spacing: 12) {
						Text(rule.type)
							.foregroundColor(.secondary)
						if rule.size > 0 {
							Text(String(format: NSLocalizedString("size: %lld", comment: ""), rule.size))
								.font(.system(size: 12))
								.foregroundColor(.secondary)

						}
					}
					.frame(width: 200, alignment: .leading)
					
					Text(rule.proxy ?? "")
						.foregroundColor({
							switch rule.proxy {
							case "DIRECT":
								return .orange
							case "REJECT", "REJECT-DROP":
								return .red
							default:
								return .blue
							}
						}())
				}
			}
		}
    }
	
	
}

struct RulesRowView_Previews: PreviewProvider {
    static var previews: some View {
		RuleItemView(index: 114, rule: .init(type: "DIRECT", payload: "cn", proxy: "GeoSite"))
    }
}
