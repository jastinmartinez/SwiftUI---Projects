import Foundation
import SwiftUI

/// Composes the expanded playback screen from stateless presentation components.
///
/// The view receives one immutable model and owns only layout. Reducer state,
/// command authorization, localization, and callbacks are projected by the adapter.
struct PlaybackView: View {
    let model: Model

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    SongArtworkView(
                        model: .init(
                            artworkURL: model.artworkURL,
                            size: 300,
                            cornerRadius: 24
                        )
                    )

                    PlaybackMetadataView(model: model.metadata)
                }

                VStack(spacing: 12) {
                    if let timeline = model.timeline {
                        PlaybackTimelineView(model: timeline)
                    }

                    if let skipControls = model.skipControls {
                        PlaybackSkipControlsView(model: skipControls)
                    }
                }

                VStack(spacing: 16) {
                    PlaybackControlsView(model: model.controls)
                    PlaybackUtilityControlsView(model: model.utilityControls)
                }

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
    /// The immutable presentation contract for the expanded playback screen.
    ///
    /// Optional timeline and skip-control models determine whether those sections
    /// are rendered; the view does not infer their availability.
    struct Model {
        let artworkURL: URL?
        let metadata: PlaybackMetadataView.Model
        let timeline: PlaybackTimelineView.Model?
        let skipControls: PlaybackSkipControlsView.Model?
        let controls: PlaybackControlsView.Model
        let utilityControls: PlaybackUtilityControlsView.Model
        let eligibility: PlaybackEligibilityNoticeView.Model
    }
}
