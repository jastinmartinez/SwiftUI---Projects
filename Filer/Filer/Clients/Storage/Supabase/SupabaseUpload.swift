import Foundation

enum SupabaseUpload {
    struct Request: Equatable, Sendable {
        let endpoint: URL
        let headers: [String: String]

        nonisolated init(endpoint: URL, headers: [String: String]) {
            self.endpoint = endpoint
            self.headers = headers
        }
    }

    nonisolated static func request(for media: ImportedMedia, config: SupabaseConfig) -> Request {
        Request(
            endpoint: config.projectURL.appending(path: "storage/v1/upload/resumable"),
            headers: headers(for: media, config: config)
        )
    }

    private nonisolated static func headers(for media: ImportedMedia, config: SupabaseConfig) -> [String: String] {
        [
            "Authorization": "Bearer \(config.anonKey)",
            "apikey": config.anonKey,
            "Upload-Metadata": metadata(media, bucket: config.bucket),
            "x-upsert": "true",
        ]
    }

    // "<key> <base64(value)>,…"  — custom "name" key round-trips the display filename (§9)
    private nonisolated static func metadata(_ media: ImportedMedia, bucket: String) -> String {
        [
            "bucketName": bucket,
            "objectName": media.id,
            "contentType": media.contentType,
            "cacheControl": "3600",
            "name": media.name,
        ]
        .map { "\($0.key) \(Data($0.value.utf8).base64EncodedString())" }
        .joined(separator: ",")
    }
}
