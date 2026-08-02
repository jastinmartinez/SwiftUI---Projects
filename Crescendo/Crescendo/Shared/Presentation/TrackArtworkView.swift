import Foundation
import SwiftUI
import UIKit

/// Displays provider-neutral track artwork with a consistent music placeholder.
///
/// App-managed file URLs render directly from local storage. Network URLs retain
/// an asynchronous loading lifecycle.
struct TrackArtworkView: View {
    let model: Model

    var body: some View {
        artwork
            .frame(width: model.size, height: model.size)
            .clipShape(RoundedRectangle(cornerRadius: model.cornerRadius))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = model.artworkURL {
            if artworkURL.isFileURL {
                if let image = UIImage(contentsOfFile: artworkURL.path) {
                    artworkImage(Image(uiImage: image))
                } else {
                    placeholder
                }
            } else {
                AsyncImage(url: artworkURL) { image in
                    artworkImage(image)
                } placeholder: {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private func artworkImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}

extension TrackArtworkView {
    /// The immutable presentation contract for provider-neutral track artwork.
    struct Model: Equatable {
        let artworkURL: URL?
        let size: CGFloat
        let cornerRadius: CGFloat
    }
}
