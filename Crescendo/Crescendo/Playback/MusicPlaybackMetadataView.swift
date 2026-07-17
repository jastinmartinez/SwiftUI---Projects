import SwiftUI

/// Displays the selected song and current playback status.
struct MusicPlaybackMetadataView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 6) {
            Text(model.title)
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let artistName = model.artistName {
                Text(artistName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let providerAttribution = model.providerAttribution {
                Text(providerAttribution)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }

            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension MusicPlaybackMetadataView {
    struct Model: Equatable {
        let title: String
        let artistName: String?
        let providerAttribution: String?
        let statusText: String
    }
}
