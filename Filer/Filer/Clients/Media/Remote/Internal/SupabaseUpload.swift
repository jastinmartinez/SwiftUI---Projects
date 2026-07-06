import Foundation

enum SupabaseUpload {
    static func request(for media: ImportedMedia, config: SupabaseConfig) -> MediaRemoteClient.UploadRequest {
        MediaRemoteClient.UploadRequest(
            endpoint: config.projectURL.appending(path: "storage/v1/upload/resumable"),
            commonHeaders: SupabaseStorageHeaders.auth(config: config),
            createHeaders: SupabaseStorageHeaders.create(media: media, config: config)
        )
    }
}
