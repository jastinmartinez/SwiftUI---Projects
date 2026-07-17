import Foundation
import SwiftUI

/// Presents a compact summary of the current song.
struct NowPlayingBarView: View {
    let model: Model

    var body: some View {
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

                        if let progress = model.progress {
                            HStack(spacing: 8) {
                                Text(model.elapsedTimeText)
                                PlaybackProgressView(progress: progress)
                                if let durationText = model.durationText {
                                    Text(durationText)
                                }
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
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
                    .frame(width: 52, height: 52)
                    .background(LinearGradient.crescendoSpectrum, in: Circle())
            }
            .accessibilityLabel(
                model.isPlaying ? Locs.MusicPlayback.pause : Locs.MusicPlayback.play
            )
            .disabled(!model.isPlaying && !model.isPlayEnabled)
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }
}

extension NowPlayingBarView {
    struct Model {
        let title: String
        let artistName: String
        let artworkURL: URL?
        let isPlaying: Bool
        let isPlayEnabled: Bool
        let elapsedTimeText: String
        let durationText: String?
        let progress: Double?
        let onOpenPlayer: () -> Void
        let onTogglePlayPause: () -> Void
    }
}
