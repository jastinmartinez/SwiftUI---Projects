import Dependencies
import Foundation

extension MediaTransferClient: DependencyKey {
    static var liveValue: MediaTransferClient {
        live(cacheClient: .liveValue, uploadClient: .liveValue, downloadClient: .liveValue, remoteClient: .liveValue)
    }

    static func live(
        cacheClient: MediaCacheClient,
        uploadClient: MediaUploadClient,
        downloadClient: MediaDownloadClient,
        remoteClient: MediaRemoteClient
    ) -> MediaTransferClient {
        let list: List = {
            try await remoteClient.list()
        }
        let upload: Upload = { media in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let source = try await cacheClient.uploadSource(media.id)
                        let uploadMedia = ImportedMedia(
                            metadata: media.metadata.with(size: source.size),
                            fileURL: source.localURL
                        )
                        let uploadRequest = remoteClient.uploadRequest(uploadMedia)
                        let uploadSource = MediaUploadClient.UploadSource(
                            size: Int(source.size),
                            read: { offset, length in
                                try await cacheClient.readUpload(source.key, offset, length)
                            }
                        )
                        for try await event in uploadClient.run(
                            MediaUploadClient.Request(
                                endpoint: uploadRequest.endpoint,
                                commonHeaders: uploadRequest.commonHeaders,
                                createHeaders: uploadRequest.createHeaders
                            ),
                            uploadSource
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
                        let downloadRequest = try remoteClient.downloadRequest(file)
                        let target = try await cacheClient.prepareDownload(file.id)
                        let sink = MediaDownloadClient.DownloadSink(
                            currentOffset: { try await cacheClient.downloadOffset(target.key) },
                            write: { data, offset in try await cacheClient.writeDownload(target.key, data, offset) }
                        )
                        for try await progress in downloadClient.run(
                            MediaDownloadClient.Request(
                                url: downloadRequest.url,
                                headers: downloadRequest.headers,
                                expectedSize: file.size
                            ),
                            sink
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

        return MediaTransferClient(
            list: list,
            upload: upload,
            download: download
        )
    }
}
