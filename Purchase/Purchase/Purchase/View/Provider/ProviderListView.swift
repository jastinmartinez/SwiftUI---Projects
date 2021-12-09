//
//  ProviderListView.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct ProviderListView: View {
    
    @StateObject var providerController = PurchaseController<Provider>()
    
    var body: some View {
        
        List {
            
            ForEach(providerController.data, id: \.id) { provider in
                
                NavigationLink(destination: ProviderCreateAndUpdateOperationView(providerController: providerController, provider: provider).navigationTitle("Modificar")) {
                    ProviderView(provider: provider)
                }
            }
            .onDelete(perform: providerController.remove)
            
        }
        .refreshable { providerController.getAll() }
        .toolbar {
            NavigationLink(destination: ProviderCreateAndUpdateOperationView(providerController: providerController).navigationTitle("Nuevo")) {
                
                Text("Nuevo")
            }
        }
    }
}

struct ProviderListView_Previews: PreviewProvider {
    static var previews: some View {
        ProviderListView()
    }
}
