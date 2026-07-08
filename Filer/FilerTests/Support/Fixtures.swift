@testable import Filer
import Foundation
import Testing

// Shared test-data builders. Each factory ships ready-to-use defaults so a test
// arranges only the field it actually asserts on — everything else stays out of
// the way. Prefer these over hand-built literals.

// MARK: - MediaMetadata

extension MediaMetadata {
    static func sample(
        id: String = "abc.jpg",
        name: String = "Holiday Photo",
        contentType: String = "image/jpeg",
        kind: MediaKind = .image,
        size: Int64? = 2048
    ) -> MediaMetadata {
        MediaMetadata(id: id, name: name, contentType: contentType, kind: kind, size: size)
    }
}

// MARK: - ImportedMedia

extension ImportedMedia {
    /// Backed by a `/tmp/<id>` file URL unless one is supplied.
    static func sample(
        id: String = "abc.jpg",
        name: String = "Holiday Photo",
        contentType: String = "image/jpeg",
        kind: MediaKind = .image,
        size: Int64? = 2048,
        fileURL: URL? = nil
    ) -> ImportedMedia {
        ImportedMedia(
            metadata: .sample(id: id, name: name, contentType: contentType, kind: kind, size: size),
            fileURL: fileURL ?? URL(fileURLWithPath: "/tmp/\(id)")
        )
    }
}

// MARK: - FileItem

extension FileItem {
    static func sample(
        id: String = "abc.jpg",
        name: String = "Holiday Photo",
        contentType: String = "image/jpeg",
        kind: MediaKind = .image,
        size: Int64? = 2048,
        status: Status = .remote
    ) -> FileItem {
        FileItem(
            metadata: .sample(id: id, name: name, contentType: contentType, kind: kind, size: size),
            status: status
        )
    }
}

// MARK: - SupabaseConfig

extension SupabaseConfig {
    static func sample(
        projectURL: String = "https://xyz.supabase.co",
        anonKey: String = "anon-123",
        bucket: String = "media"
    ) throws -> SupabaseConfig {
        try SupabaseConfig(projectURL: #require(URL(string: projectURL)), anonKey: anonKey, bucket: bucket)
    }
}
