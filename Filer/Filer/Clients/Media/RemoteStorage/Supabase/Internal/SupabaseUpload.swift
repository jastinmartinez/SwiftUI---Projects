import Foundation

enum SupabaseUpload {
    struct Request: Equatable, Sendable {
        let endpoint: URL
        /// Sent with every request in the upload (authentication).
        let commonHeaders: [String: String]
        /// Sent only with the create (POST): object metadata and upsert.
        let createHeaders: [String: String]
    }

    static func request(for media: ImportedMedia, config: SupabaseConfig) -> Request {
        Request(
            endpoint: config.projectURL.appending(path: "storage/v1/upload/resumable"),
            commonHeaders: SupabaseStorageHeaders.auth(config: config),
            createHeaders: SupabaseStorageHeaders.create(media: media, config: config)
        )
    }
}
