//
//  SwiftUIView.swift
//  
//
//

import SwiftUI

struct SidebarLabel: View {
	@State var item: SidebarItem
	
    var body: some View {
		Label {
			Text(LocalizedStringKey(item.rawValue))
		} icon: {
            Image(systemName: item.icon)
				.foregroundColor(.accentColor)
		}
    }
}

struct SidebarLabel_Previews: PreviewProvider {
    static var previews: some View {
		SidebarLabel(item: .overview)
    }
}
