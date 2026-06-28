import Dependencies
import Foundation

extension MediaDownloadStoreClient: DependencyKey {
    static let liveValue = live(contentStorage: .liveValue)

    static func live(
        contentStorage: MediaContentStorageClient
    ) -> MediaDownloadStoreClient {
        let prepareDownloadTarget: PrepareDownloadTarget = { file in
            let target = try await contentStorage.prepareDownloadTarget(file.id)
            return DownloadTarget(
                file: file,
                key: target.key,
                localURL: target.localURL
            )
        }

        let makeDownloadSink: MakeDownloadSink = { target in
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
            prepareDownloadTarget: prepareDownloadTarget,
            makeDownloadSink: makeDownloadSink
        )
    }
}
