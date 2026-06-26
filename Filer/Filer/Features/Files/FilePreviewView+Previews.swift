import SwiftUI

#Preview("Image") {
    FilePreviewView(model: .image(URL(string: "https://picsum.photos/600")!))
}

#Preview("Video") {
    FilePreviewView(model: .video(URL(string: "https://example.com/clip.mp4")!))
}
