import Dependencies
import Foundation
import Storage

extension MediaRemoteStorageClient: DependencyKey {
    static var liveValue: MediaRemoteStorageClient {
        make(
            config: .loadFromBundle(),
            uploadStore: .liveValue,
            downloadStore: .liveValue
        )
    }

    static func make(
        config: SupabaseConfig,
        uploadStore: MediaUploadStoreClient,
        downloadStore: MediaDownloadStoreClient
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
                        let storedUploadSource = try await uploadStore.loadUploadSource(media)
                        let uploadRequest = SupabaseUpload.request(for: storedUploadSource.media, config: config)
                        let resumableUploadSource = try ResumableUploader.UploadSource.file(
                            storedUploadSource.localURL,
                            fileManager: .default
                        )
                        for try await progress in ResumableUploader(
                            transport: .live(session: .shared),
                            retryPolicy: .default
                        )
                        .upload(
                            ResumableUploader.Request(
                                endpoint: uploadRequest.endpoint,
                                headers: uploadRequest.headers
                            ),
                            source: resumableUploadSource
                        ) {
                            continuation.yield(.progress(progress))
                        }
                        continuation.yield(.finished(FileItem(uploaded: storedUploadSource.media)))
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
                        let downloadTarget = try await downloadStore.prepareDownloadTarget(file)
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
                            sink: downloadStore.makeDownloadSink(downloadTarget)
                        ) {
                            continuation.yield(.progress(progress))
                        }
                        continuation.yield(.finished(downloadTarget.localURL))
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
