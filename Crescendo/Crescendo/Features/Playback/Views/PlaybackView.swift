import Foundation
import SwiftUI

/// Renders playback presentation from explicit values and callbacks.
struct PlaybackView: View {
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

                PlaybackMetadataView(model: model.metadata)

                if let timeline = model.timeline {
                    PlaybackTimelineView(model: timeline)
                }

                PlaybackControlsView(model: model.controls)
                PlaybackEligibilityNoticeView(model: model.eligibility)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

extension PlaybackView {
    /// The immutable presentation contract for the playback screen.
    struct Model {
        let artworkURL: URL?
        let metadata: PlaybackMetadataView.Model
        let timeline: PlaybackTimelineView.Model?
        let controls: PlaybackControlsView.Model
        let eligibility: PlaybackEligibilityNoticeView.Model
    }
}
