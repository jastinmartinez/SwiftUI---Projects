//
//  ProviderView.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct ProviderView: View {
    
    var provider: Provider
    
    var body: some View {
        
        VStack {
            
            HStack {
                Spacer()
                LogoView(name: "provider")
            }
            
            HStack(spacing: 20) {
                
                
                Text("\(provider.id!)")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
                
                HStack {
                    Spacer()
                    VStack(alignment: .trailing) {
                        
                        Text(provider.personID)
                        Text(provider.comercialName)
                        Text(provider.state.toString())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct ProviderView_Previews: PreviewProvider {
    static var previews: some View {
        ProviderView(provider: Provider(id: 1, personID: "402-0048778-9", comercialName: "Santo Criollo", state: true))
    }
}
