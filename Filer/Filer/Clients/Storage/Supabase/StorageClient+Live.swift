import Dependencies
import Foundation
import Storage

extension StorageClient: DependencyKey {
    static let liveValue = make(config: .loadFromBundle())

    static func make(config: SupabaseConfig) -> StorageClient {
        let storageURL = config.projectURL.appending(path: "storage/v1")
        let headers: [String: String] = [
            "Authorization": "Bearer \(config.anonKey)",
            "apikey": config.anonKey,
        ]
        let storage = SupabaseStorageClient(
            configuration: StorageClientConfiguration(url: storageURL, headers: headers, logger: nil)
        )
        return StorageClient(
            list: {
                try await storage.from(config.bucket).list().compactMap(FileItem.init)
            },
            upload: { media in
                let req = SupabaseUpload(media, config: config)
                return ResumableUploader(session: .shared)
                    .upload(media.fileURL, to: req.endpoint, headers: req.headers)
                    .mapToUploadEvent(media)
            },
            download: { file in
                do {
                    let url = try storage.from(config.bucket).getPublicURL(path: file.id)
                    let dest = FileManager.default.cachesURL(for: file)
                    return RangedDownloader(session: .shared)
                        .download(url, to: dest, headers: [:], expectedSize: file.size)
                        .mapToDownloadEvent(dest)
                } catch {
                    return AsyncThrowingStream { $0.finish(throwing: error) }
                }
            }
        )
    }
}
