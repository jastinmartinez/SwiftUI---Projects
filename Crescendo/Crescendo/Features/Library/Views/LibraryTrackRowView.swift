import Foundation
import SwiftUI

/// Renders one tappable Library item from immutable display values.
///
/// The row owns layout and accessibility only. It does not hold a Store,
/// localize metadata, resolve files, compute Library policy, or control
/// playback.
struct LibraryTrackRowView: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(spacing: 14) {
                TrackArtworkView(
                    model: .init(
                        artworkURL: model.artworkURL,
                        size: 58,
                        cornerRadius: 10
                    )
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(model.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(model.album)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

extension LibraryTrackRowView {
    /// The immutable presentation contract for one Library row.
    struct Model: Identifiable {
        let id: TrackID
        let title: String
        let artist: String
        let album: String
        let artworkURL: URL?
        let onTap: () -> Void
    }
}
