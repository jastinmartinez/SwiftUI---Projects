//
//  RequeriedMark.swift
//  Purchase
//
//  Created by Jastin on 11/11/21.
//

import SwiftUI

struct RequiredMark: View {
    var body: some View {
        Text("*")
            .foregroundColor(.red)
    }
}

struct RequeriedMark_Previews: PreviewProvider {
    static var previews: some View {
        RequiredMark()
    }
}
