import Foundation

extension FilePreviewView {
    enum Model: Equatable {
        case image(URL)
        case video(URL)
    }
}

extension FilePreviewView.Model {
    init(_ item: FilesFeature.PreviewItem) {
        self = switch item.kind {
        case .image: .image(item.url)
        case .video: .video(item.url)
        }
    }
}
