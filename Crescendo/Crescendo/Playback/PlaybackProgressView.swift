import SwiftUI

struct PlaybackProgressView: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)

            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient.crescendoSpectrum)
                        .frame(width: proxy.size.width * clampedProgress)
                }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
