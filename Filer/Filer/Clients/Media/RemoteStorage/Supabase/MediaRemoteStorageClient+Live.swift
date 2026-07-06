import Dependencies
import Foundation
import Storage

extension MediaRemoteStorageClient: DependencyKey {
    static var liveValue: MediaRemoteStorageClient {
        make(config: .loadFromBundle(), cache: .liveValue)
    }

    static func make(
        config: SupabaseConfig,
        cache: MediaCacheClient
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
                        let source = try await cache.uploadSource(media.id)
                        let uploadMedia = ImportedMedia(
                            metadata: media.metadata.with(size: source.size),
                            fileURL: source.localURL
                        )
                        let uploadRequest = SupabaseUpload.request(for: uploadMedia, config: config)
                        let resumableUploadSource = ResumableUploader.UploadSource(
                            size: Int(source.size),
                            read: { offset, length in
                                try await cache.readUpload(source.key, offset, length)
                            }
                        )
                        for try await event in ResumableUploader(
                            transport: .live(session: .shared),
                            retryPolicy: .default,
                            connectivity: .live,
                            sleeper: .live
                        )
                        .upload(
                            ResumableUploader.Request(
                                endpoint: uploadRequest.endpoint,
                                commonHeaders: uploadRequest.commonHeaders,
                                createHeaders: uploadRequest.createHeaders
                            ),
                            source: resumableUploadSource
                        ) {
                            switch event {
                            case let .progress(progress):
                                continuation.yield(.progress(progress))
                            case .waitingForConnectivity:
                                continuation.yield(.reconnecting)
                            }
                        }
                        continuation.yield(.finished(FileItem(uploaded: uploadMedia)))
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
                        let downloadURL = try storage.from(config.bucket).getPublicURL(path: file.id)
                        let target = try await cache.prepareDownload(file.id)
                        let sink = RangedDownloader.DownloadSink(
                            currentOffset: { try await cache.downloadOffset(target.key) },
                            write: { data, offset in try await cache.writeDownload(target.key, data, offset) }
                        )
                        for try await progress in RangedDownloader(
                            transport: .live(session: .shared),
                            retryPolicy: .default
                        )
                        .download(
                            RangedDownloader.Request(
                                url: downloadURL,
                                headers: SupabaseStorageHeaders.download(config: config),
                                expectedSize: file.size
                            ),
                            sink: sink
                        ) {
                            continuation.yield(.progress(progress))
                        }
                        continuation.yield(.finished(target.localURL))
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
