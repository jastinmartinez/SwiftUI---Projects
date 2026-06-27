import Foundation

// Cache-backed media ready for upload and local preview.
struct ImportedMedia: Equatable, Sendable {
    let id: String // intended object path ("<uuid>.<ext>")
    let name: String // display filename resolved at import
    let fileURL: URL // cached local file
    let contentType: String // MIME to Upload-Metadata and Kind
    let kind: FileItem.Kind
    let size: Int64 // always known from cache
}
