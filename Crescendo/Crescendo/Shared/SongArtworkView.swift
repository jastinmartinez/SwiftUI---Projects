import Foundation
import SwiftUI

/// Displays remote song artwork with a consistent music placeholder.
struct SongArtworkView: View {
    let model: Model

    var body: some View {
        AsyncImage(url: model.artworkURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            ZStack {
                Color.secondary.opacity(0.15)
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: model.size, height: model.size)
        .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius))
        .accessibilityHidden(true)
    }
}

extension SongArtworkView {
    /// The immutable presentation contract for remote song artwork.
    struct Model: Equatable {
        let artworkURL: URL?
        let size: CGFloat
        let cornerRadius: CGFloat
    }
}
