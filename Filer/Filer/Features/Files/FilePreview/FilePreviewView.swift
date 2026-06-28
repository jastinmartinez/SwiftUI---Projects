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

#Preview("Image") {
    FilePreviewView(model: .image(URL(string: "https://picsum.photos/600")!))
}

#Preview("Video") {
    FilePreviewView(model: .video(URL(string: "https://example.com/clip.mp4")!))
}
