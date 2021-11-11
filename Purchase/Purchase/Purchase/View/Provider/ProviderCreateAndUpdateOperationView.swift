//
//  ProviderCreateAndUpdateOperationView.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI
import Combine

struct ProviderCreateAndUpdateOperationView: View {
    
    @Environment(\.presentationMode) var presetation
    
    @StateObject var providerController: ProviderController
    
    @State var provider: Provider = Provider(id: nil, personID: "", comercialName: "", state: true)
   
    @State private(set) var isClicked = false
    
    @State private(set) var showValidation = false
    
    fileprivate func isProcessComplete(state: Bool) {
        
        if state {
            
            isClicked = !state
            
            presetation.wrappedValue.dismiss()
        }
    }
   
    fileprivate func personIDValidation(_ personID: String) {
        
        self.provider.personID = String(provider.personID.prefix(11))
        
        let justNumner = personID.filter({"0123456789".contains($0)})
        
        if justNumner != personID {
            
            provider.personID = justNumner
        }
    
        if !UserDocument().verify(personID) {
            
            showValidation = true
        }
        else {
            
            showValidation = false
        }
    }
    
    var body: some View {

        Form {
            Section("Proveedor") {
                
                
                if provider.id != nil {
                    
                    Text("\(provider.id!)")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .bold()
                }
                
                HStack {
                    
                    
                    if provider.personID.isEmpty {
                    
                        RequiredMark()
                    }
                    
                    VStack {
                        TextField("Cedula", text: $provider.personID)
                            .onChange(of: provider.personID) { personIDValidation($0) }
                        
                        if showValidation {
                            
                          Text("Cedula Invalida")
                                .foregroundColor(.red)
                        }
                    }
                    
                }
                
                
                HStack {
                    
                    if provider.comercialName.isEmpty {
                    
                        RequiredMark()
                    }
                    
                    TextField("Nombre Comercial", text: $provider.comercialName)
                }
                
                StatusPicker(status: $provider.state)
                
                HStack {
                    
                    Spacer()
                    
                    if !isClicked {
                        
                        Button("Guardar") {
                            
                            guard !provider.personID.isEmpty && !provider.comercialName.isEmpty && !showValidation else { return }
                            
                            isClicked = !isClicked
                            
                            if provider.id != nil {
                                
                                providerController.update(provider, notify: isProcessComplete)
                            }
                            else {
                                
                                providerController.create(provider, notify: isProcessComplete)
                            }
                        }
                    }
                    else {
                        ActivityIndicator(isAnimating: $isClicked, style: .medium)
                    }
                   
                }
            }
        }
    }
}

struct ProviderCreateAndUpdateOperationView_Previews: PreviewProvider {
    static var previews: some View {
        ProviderCreateAndUpdateOperationView(providerController: ProviderController())
    }
}
