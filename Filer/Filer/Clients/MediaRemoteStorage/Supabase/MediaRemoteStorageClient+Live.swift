import Dependencies
import Foundation
import Storage

extension MediaRemoteStorageClient: DependencyKey {
    static var liveValue: MediaRemoteStorageClient {
        make(config: .loadFromBundle())
    }

    static func make(
        config: SupabaseConfig,
        uploadStore: MediaUploadStoreClient = .liveValue,
        downloadStore: MediaDownloadStoreClient = .liveValue
    ) -> MediaRemoteStorageClient {
        let storageURL = config.projectURL.appending(path: "storage/v1")
        let headers: [String: String] = [
            "Authorization": "Bearer \(config.anonKey)",
            "apikey": config.anonKey,
        ]
        let storage = SupabaseStorageClient(
            configuration: StorageClientConfiguration(
                url: storageURL,
                headers: headers,
                logger: nil
            )
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
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let url = try storage.from(config.bucket).getPublicURL(path: file.id)
                        let target = try await downloadStore.downloadTarget(file)
                        for try await event in RangedDownloader(transport: .live(session: .shared))
                            .download(
                                RangedDownloader.Request(
                                    url: url,
                                    headers: SupabaseStorageHeaders.download(config: config),
                                    expectedSize: file.size
                                ),
                                sink: downloadStore.downloadSink(target)
                            )
                            .mapToDownloadEvent(target.localURL)
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

        return MediaRemoteStorageClient(
            list: list,
            upload: upload,
            download: download
        )
    }
}
