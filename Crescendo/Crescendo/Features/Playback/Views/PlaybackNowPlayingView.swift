import Foundation
import SwiftUI

/// Presents a compact summary of the current song.
struct PlaybackNowPlayingView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button(action: model.onOpenPlayer) {
                    HStack(spacing: 12) {
                        SongArtworkView(
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
                .accessibilityLabel(
                    model.isPlaying ? Locs.Playback.pause : Locs.Playback.play
                )
                .disabled(!model.isPlaying && !model.isPlayEnabled)
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
    struct Model {
        let title: String
        let artistName: String
        let artworkURL: URL?
        let isPlaying: Bool
        let isPlayEnabled: Bool
        let timeline: PlaybackTimelineView.Model?
        let onOpenPlayer: () -> Void
        let onTogglePlayPause: () -> Void
    }
}
