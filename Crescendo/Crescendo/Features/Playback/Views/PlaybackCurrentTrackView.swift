import Foundation
import SwiftUI

/// Renders the expanded player's current-track presentation.
struct PlaybackCurrentTrackView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 16) {
            TrackArtworkView(
                model: .init(
                    artworkURL: model.artworkURL,
                    size: 300,
                    cornerRadius: 24
                )
            )

            PlaybackMetadataView(model: model.metadata)
        }
    }
}

extension PlaybackCurrentTrackView {
    /// The artwork and metadata for the track presented by expanded playback.
    struct Model {
        let artworkURL: URL?
        let metadata: PlaybackMetadataView.Model
    }
}

extension PlaybackCurrentTrackView.Model {
    /// Localized copy used while projecting transient playback state.
    struct Strings {
        let loading: String
        let resourceUnavailable: String
        let unsupportedResource: String
        let preparationFailed: String
        let playbackFailed: String
    }
}
