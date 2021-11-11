//
//  StatusPicker.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct StatusPicker: View {
    
    @Binding var status: Bool
    
    var body: some View {
    
        Picker("Estado", selection: $status) {
            
            Text("Activo").tag(true)
            
            Text("Inactivo").tag(false)
        }
        .pickerStyle(.segmented)
    }
}

struct StatusPicker_Previews: PreviewProvider {
  
    static var previews: some View {
        StatusPicker(status: .constant(true))
    }
}
