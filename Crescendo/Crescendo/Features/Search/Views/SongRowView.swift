import SwiftUI

/// Displays provider-neutral song metadata without owning feature state.
struct SongRowView: View {
    let model: Model

    var body: some View {
        HStack(spacing: 14) {
            SongArtworkView(
                model: .init(
                    artworkURL: model.artworkURL,
                    size: 64,
                    cornerRadius: 10
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(model.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let durationText = model.durationText {
                Text(durationText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension SongRowView {
    /// The immutable presentation contract for a catalog result row.
    struct Model: Equatable, Identifiable {
        let id: MusicItemID
        let title: String
        let artistName: String
        let artworkURL: URL?
        let durationText: String?
    }
}
