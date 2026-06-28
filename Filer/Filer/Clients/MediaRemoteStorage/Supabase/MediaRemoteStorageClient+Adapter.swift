import Foundation
import Storage

// MARK: - FileObject → FileItem

// framework → domain (list). FileObject.metadata is an untyped [String: AnyJSON]? —
// no typed .size/.mimetype/.displayName members; read by key with AnyJSON unwrapping.
// Non-media objects map to nil so the live `list` compactMaps them away (§12).
extension FileItem {
    init?(_ object: FileObject) {
        let meta = object.metadata
        guard let contentType = meta?["mimetype"]?.stringValue,
              let kind = MediaKind(mimeType: contentType)
        else { return nil }
        let metadata = MediaMetadata(
            id: object.name,
            name: meta?["name"]?.stringValue ?? object.name,
            contentType: contentType,
            kind: kind,
            size: meta?["size"]?.doubleValue.map(Int64.init)
        )
        self.init(remote: metadata)
    }
}
