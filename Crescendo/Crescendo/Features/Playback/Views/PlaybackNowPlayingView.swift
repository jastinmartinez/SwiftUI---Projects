import Foundation
import SwiftUI

/// Presents the compact playback surface shown above the app's primary content.
///
/// Opening the expanded player and toggling transport are independent callbacks.
/// Confirmed metadata and immediate Play/Pause presentation arrive through the
/// immutable model.
struct PlaybackNowPlayingView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button(action: model.onOpenPlayer) {
                    HStack(spacing: 12) {
                        TrackArtworkView(
                            model: .init(
                                artworkURL: model.artworkURL,
                                size: 56,
                                cornerRadius: 10
                            )
                        )
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(model.artistName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: model.onTogglePlayPause) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(
                            .easeInOut(duration: 0.2),
                            value: model.isPlaying
                        )
                        .frame(width: 52, height: 52)
                        .background(LinearGradient.crescendoSpectrum, in: Circle())
                }
                .accessibilityLabel(model.playPauseAccessibilityLabel)
                .disabled(!model.isPlayPauseEnabled)
            }

            if let timeline = model.timeline {
                PlaybackTimelineView(model: timeline)
            }
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }
}

extension PlaybackNowPlayingView {
    /// The immutable presentation contract for compact playback.
    ///
    /// `isPlaying` controls the visible transport action, while
    /// `isPlayPauseEnabled` applies the reducer-owned permission to either action.
    struct Model {
        let title: String
        let artistName: String
        let artworkURL: URL?
        let isPlaying: Bool
        let isPlayPauseEnabled: Bool
        let playPauseAccessibilityLabel: String
        let timeline: PlaybackTimelineView.Model?
        let onOpenPlayer: () -> Void
        let onTogglePlayPause: () -> Void
    }
}

extension PlaybackNowPlayingView.Model {
    /// Localized actions rendered by compact playback.
    struct Strings {
        let play: String
        let pause: String
    }
}
