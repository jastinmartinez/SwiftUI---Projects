import Foundation

/// Builds Supabase Storage headers.
///
/// This type owns provider-specific header composition. Transfer engines receive
/// headers as request data and do not know Supabase authentication semantics.
enum SupabaseStorageHeaders {
    static func auth(config: SupabaseConfig) -> [String: String] {
        [
            "Authorization": "Bearer \(config.anonKey)",
            "apikey": config.anonKey,
        ]
    }

    /// Headers unique to the resumable create (POST): object metadata and upsert.
    /// Auth is not included — it rides on every request via `auth(config:)`.
    static func create(media: ImportedMedia, config: SupabaseConfig) -> [String: String] {
        [
            "Upload-Metadata": encodedMetadata(media, bucket: config.bucket),
            "x-upsert": "true",
        ]
    }

    static func download(config: SupabaseConfig) -> [String: String] {
        auth(config: config)
    }

    private static func encodedMetadata(_ media: ImportedMedia, bucket: String) -> String {
        [
            ("bucketName", bucket),
            ("objectName", media.metadata.id),
            ("contentType", media.metadata.contentType),
            ("cacheControl", "3600"),
            ("name", media.metadata.name),
        ]
        .map { "\($0.0) \(Data($0.1.utf8).base64EncodedString())" }
        .joined(separator: ",")
    }
}
