//
//  MeasureUnitView.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct MeasureUnitView: View {
    
    var measureUnit: MeasureUnit
    
    var body: some View {
        
        VStack {
            
            HStack {
                Spacer()
                LogoView(name: "measureunit")
            }
            
            HStack(spacing: 20) {
                
                
                Text("\(measureUnit.id!)")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
                
                HStack {
                    Spacer()
                    VStack(alignment: .trailing) {
                        
                        Text(measureUnit.description)
                        Text(measureUnit.state.toString())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}


struct MeasureUnitView_Previews: PreviewProvider {
    static var previews: some View {
        MeasureUnitView(measureUnit: MeasureUnit(id: 1, description: "ejemplo", state: true))
    }
}
