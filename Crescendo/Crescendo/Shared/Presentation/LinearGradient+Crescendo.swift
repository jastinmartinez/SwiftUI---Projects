import SwiftUI

/// Provides Crescendo's spectrum colors to SwiftUI and UIKit presentation
/// renderers.
///
/// The palette owns visual identity only. It carries no playback state or
/// behavior and remains outside the playback domain.
enum CrescendoSpectrum {
    static let colors: [Color] = [
        Color(red: 0.24, green: 0.24, blue: 0.96),
        Color(red: 0.56, green: 0.16, blue: 0.94),
        Color(red: 0.94, green: 0.12, blue: 0.66),
    ]
}

extension LinearGradient {
    static let crescendoSpectrum = Self(
        colors: CrescendoSpectrum.colors,
        startPoint: .leading,
        endPoint: .trailing
    )
}
