import AVKit
import SwiftUI

struct FilePreviewView: View {
    let model: Model

    var body: some View {
        switch model {
        case let .image(url):
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
        case let .video(url):
            VideoPlayer(player: AVPlayer(url: url))
        }
    }
}
