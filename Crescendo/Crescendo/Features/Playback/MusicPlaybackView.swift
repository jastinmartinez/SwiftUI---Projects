import Foundation
import SwiftUI

/// Renders playback presentation from explicit values and callbacks.
struct MusicPlaybackView: View {
    let model: Model

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SongArtworkView(
                    model: .init(
                        artworkURL: model.artworkURL,
                        size: 300,
                        cornerRadius: 24
                    )
                )

                MusicPlaybackMetadataView(model: model.metadata)

                if let timeline = model.timeline {
                    MusicPlaybackTimelineView(model: timeline)
                }

                MusicPlaybackControlsView(model: model.controls)
                PlaybackEligibilityNoticeView(model: model.eligibility)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

extension MusicPlaybackView {
    /// The immutable presentation contract for the playback screen.
    struct Model {
        let artworkURL: URL?
        let metadata: MusicPlaybackMetadataView.Model
        let timeline: MusicPlaybackTimelineView.Model?
        let controls: MusicPlaybackControlsView.Model
        let eligibility: PlaybackEligibilityNoticeView.Model
    }
}
