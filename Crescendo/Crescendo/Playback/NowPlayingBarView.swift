import Foundation
import SwiftUI

/// Presents a compact summary of the current song.
struct NowPlayingBarView: View {
    let model: Model

    var body: some View {
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
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .padding()
        }
    }
}

extension NowPlayingBarView {
    struct Model {
        let title: String
        let artistName: String
        let artworkURL: URL?
        let isPlaying: Bool
        let onOpenPlayer: () -> Void
    }
}
