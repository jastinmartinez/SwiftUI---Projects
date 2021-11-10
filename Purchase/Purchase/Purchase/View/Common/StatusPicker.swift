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
    
        Picker("Status", selection: $status) {
            
            Text("Active").tag(true)
            
            Text("Inactive").tag(false)
        }
        .pickerStyle(.segmented)
    }
}

struct StatusPicker_Previews: PreviewProvider {
  
    static var previews: some View {
        StatusPicker(status: .constant(true))
    }
}
