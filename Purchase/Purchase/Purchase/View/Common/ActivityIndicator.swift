//
//  ActivityIndicator.swift
//  Purchase
//
//  Created by Jastin on 8/11/21.
//

import Foundation
import SwiftUI

struct ActivityIndicator: UIViewRepresentable {

    @Binding var isAnimating: Bool
    
    let style: UIActivityIndicatorView.Style

    func makeUIView(context: UIViewRepresentableContext<ActivityIndicator>) -> UIActivityIndicatorView {
        
        return UIActivityIndicatorView(style: style)
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: UIViewRepresentableContext<ActivityIndicator>) {
        
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
}
