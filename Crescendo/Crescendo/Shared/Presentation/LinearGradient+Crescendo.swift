import SwiftUI

extension LinearGradient {
    static let crescendoSpectrum = Self(
        colors: [
            Color(red: 0.24, green: 0.24, blue: 0.96),
            Color(red: 0.56, green: 0.16, blue: 0.94),
            Color(red: 0.94, green: 0.12, blue: 0.66),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}
