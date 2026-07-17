import Foundation
import SwiftUI

/// Presents a compact summary of the current song.
struct NowPlayingBarView: View {
    let model: Model

    var body: some View {
        HStack {
            Button(action: model.onOpenPlayer) {
                HStack {
                    SongArtworkView(
                        model: .init(
                            artworkURL: model.artworkURL,
                            size: 48,
                            cornerRadius: 8
                        )
                    )
                    VStack(alignment: .leading) {
                        Text(model.title)
                        Text(model.artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: model.onTogglePlayPause) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!model.isPlaying && !model.isPlayEnabled)
        }
        .padding()
    }
}

extension NowPlayingBarView {
    struct Model {
        let title: String
        let artistName: String
        let artworkURL: URL?
        let isPlaying: Bool
        let isPlayEnabled: Bool
        let onOpenPlayer: () -> Void
        let onTogglePlayPause: () -> Void
    }
}
