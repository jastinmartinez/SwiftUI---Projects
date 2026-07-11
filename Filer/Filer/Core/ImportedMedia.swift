import Foundation

struct ImportedMedia: Equatable, Sendable {
    let metadata: MediaMetadata
    let fileURL: URL
}

extension ImportedMedia {
    var id: String { metadata.id }
    var name: String { metadata.name }
    var contentType: String { metadata.contentType }
    var kind: MediaKind { metadata.kind }
    var size: Int64 { metadata.size ?? 0 }
}
