import Foundation

struct MediaMetadata: Equatable, Sendable {
    let id: String
    let name: String
    let contentType: String
    let kind: MediaKind
    let size: Int64?
}

extension MediaMetadata {
    func with(size: Int64?) -> MediaMetadata {
        MediaMetadata(
            id: id,
            name: name,
            contentType: contentType,
            kind: kind,
            size: size
        )
    }
}
