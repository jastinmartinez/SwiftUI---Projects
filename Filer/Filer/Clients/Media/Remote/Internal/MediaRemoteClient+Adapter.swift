import Foundation
import Storage

extension FileItem {
    /// Maps Supabase Storage objects to media files, dropping non-media objects.
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
