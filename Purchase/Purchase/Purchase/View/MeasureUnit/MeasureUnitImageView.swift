//
//  MeasureUnitImageView.swift
//  Purchase
//
//  Created by Jastin on 10/11/21.
//

import SwiftUI

struct MeasureUnitImageView: View {
    var body: some View {
        Image("measureunit")
            .resizable()
            .frame(width: 50, height: 50)
    }
}

struct MeasureUnitImageView_Previews: PreviewProvider {
    static var previews: some View {
        MeasureUnitImageView()
    }
}
