import Foundation

// Cache-backed media ready for upload and local preview.
struct ImportedMedia: Equatable, Sendable {
    let id: String // intended object path ("<uuid>.<ext>")
    let name: String // display filename resolved at import
    let fileURL: URL // cached local file
    let contentType: String // MIME to Upload-Metadata and Kind
    let kind: FileItem.Kind
    let size: Int64 // always known from cache

    nonisolated init(
        id: String,
        name: String,
        fileURL: URL,
        contentType: String,
        kind: FileItem.Kind,
        size: Int64
    ) {
        self.id = id
        self.name = name
        self.fileURL = fileURL
        self.contentType = contentType
        self.kind = kind
        self.size = size
    }
}
