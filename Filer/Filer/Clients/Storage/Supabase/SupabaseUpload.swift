import Foundation

// wire model: the shape of a Supabase TUS upload request.
// domain → wire ⇒ init on the WIRE type (the wire value consumes the domain); ImportedMedia stays pure.
struct SupabaseUpload {
    let endpoint: URL
    let headers: [String: String] // Authorization + apikey + Upload-Metadata + x-upsert

    init(_ media: ImportedMedia, config: SupabaseConfig) {
        endpoint = config.projectURL.appending(path: "storage/v1/upload/resumable")
        headers = [
            "Authorization": "Bearer \(config.anonKey)",
            "apikey": config.anonKey,
            "Upload-Metadata": Self.metadata(media, bucket: config.bucket),
            "x-upsert": "true",
        ]
    }

    // "<key> <base64(value)>,…"  — custom "name" key round-trips the display filename (§9)
    private static func metadata(_ media: ImportedMedia, bucket: String) -> String {
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
