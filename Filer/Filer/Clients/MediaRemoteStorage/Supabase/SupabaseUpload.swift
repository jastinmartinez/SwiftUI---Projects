import Foundation

enum SupabaseUpload {
    struct Request: Equatable, Sendable {
        let endpoint: URL
        let headers: [String: String]
    }

    static func request(for media: ImportedMedia, config: SupabaseConfig) -> Request {
        Request(
            endpoint: config.projectURL.appending(path: "storage/v1/upload/resumable"),
            headers: SupabaseStorageHeaders.upload(media: media, config: config)
        )
    }
}
