import Foundation
import SwiftUI

/// Renders playback presentation from explicit values and callbacks.
struct MusicPlaybackView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 20) {
            SongArtworkView(
                model: .init(
                    artworkURL: model.artworkURL,
                    size: 240,
                    cornerRadius: 16
                )
            )
            Text(model.title)
                .font(.title2)
            if let artistName = model.artistName {
                Text(artistName)
                    .foregroundStyle(.secondary)
            }
            Text(model.statusText)
            Text(model.elapsedTimeText)
            MusicPlaybackControlsView(model: model.controls)
            PlaybackEligibilityNoticeView(model: model.eligibility)
            if let seek = model.seek {
                Slider(
                    value: Binding(
                        get: { seek.position },
                        set: { seek.onSeek($0) }
                    ),
                    in: seek.range
                )
            }
        }
        .padding()
    }
}

extension MusicPlaybackView {
    /// The immutable presentation contract for the playback screen.
    struct Model {
        let title: String
        let artistName: String?
        let artworkURL: URL?
        let statusText: String
        let elapsedTimeText: String
        let controls: MusicPlaybackControlsView.Model
        let eligibility: PlaybackEligibilityNoticeView.Model
        let seek: Seek?
    }
}

extension MusicPlaybackView.Model {
    /// Presentation values and callback required by the optional seek control.
    struct Seek {
        let position: TimeInterval
        let range: ClosedRange<TimeInterval>
        let onSeek: (TimeInterval) -> Void
    }
}
