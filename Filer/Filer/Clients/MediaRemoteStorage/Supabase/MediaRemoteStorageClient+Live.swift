import Dependencies
import Foundation
import Storage

extension MediaRemoteStorageClient: DependencyKey {
    static let liveValue = make(config: .loadFromBundle())

    static func make(
        config: SupabaseConfig,
        uploadStore: MediaUploadStoreClient = .liveValue
    ) -> MediaRemoteStorageClient {
        let storageURL = config.projectURL.appending(path: "storage/v1")
        let headers: [String: String] = [
            "Authorization": "Bearer \(config.anonKey)",
            "apikey": config.anonKey,
        ]
        let storage = SupabaseStorageClient(
            configuration: StorageClientConfiguration(url: storageURL, headers: headers, logger: nil)
        )
        let list: List = {
            try await storage.from(config.bucket).list().compactMap(FileItem.init)
        }
        let upload: Upload = { media in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let source = try await uploadStore.uploadSource(media)
                        let req = SupabaseUpload.request(for: source.media, config: config)
                        for try await event in ResumableUploader(session: .shared)
                            .upload(source.localURL, to: req.endpoint, headers: req.headers)
                            .mapToUploadEvent(source.media)
                        {
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        let download: Download = { file in
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

        return MediaRemoteStorageClient(
            list: list,
            upload: upload,
            download: download
        )
    }
}
