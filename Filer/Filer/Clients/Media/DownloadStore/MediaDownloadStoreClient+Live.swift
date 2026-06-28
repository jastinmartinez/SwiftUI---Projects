import Dependencies
import Foundation

extension MediaDownloadStoreClient: DependencyKey {
    static let liveValue = live(contentStorage: .liveValue)

    static func live(
        contentStorage: MediaContentStorageClient
    ) -> MediaDownloadStoreClient {
        let downloadTarget: DownloadTarget = { file in
            let target = try await contentStorage.prepareDownloadTarget(file.id)
            return Target(
                file: file,
                key: target.key,
                localURL: target.localURL
            )
        }

        let writeDownloadChunk: WriteDownloadChunk = { target, data, offset in
            try await contentStorage.writeDownload(target.key, data, offset)
        }

        let downloadSink: DownloadSink = { target in
            RangedDownloader.DownloadSink(
                currentOffset: {
                    try await contentStorage.downloadOffset(target.key)
                },
                write: { data, offset in
                    try await contentStorage.writeDownload(target.key, data, offset)
                }
            )
        }

        return MediaDownloadStoreClient(
            downloadTarget: downloadTarget,
            downloadSink: downloadSink,
            writeDownloadChunk: writeDownloadChunk
        )
    }
}
