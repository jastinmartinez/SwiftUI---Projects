import Foundation

enum MediaKind: Equatable, Sendable {
    case image
    case video
}

extension MediaKind {
    init?(mimeType: String?) {
        guard let mimeType, !mimeType.isEmpty else { return nil }
        if mimeType.hasPrefix("image/") {
            self = .image
        } else if mimeType.hasPrefix("video/") {
            self = .video
        } else {
            return nil
        }
    }
}
