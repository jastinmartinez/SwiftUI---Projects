import Dependencies
import Foundation

extension MediaContentStorageClient: DependencyKey {
    static let liveValue = live(
        fileStore: MediaContentFileStore(
            root: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
                path: "FilerMediaContent"
            ),
            fileManager: .default
        )
    )

    static func live(
        fileStore: MediaContentFileStore
    ) -> MediaContentStorageClient {
        let storeImport: StoreImport = { key, data in
            try await fileStore.storeImport(key, data)
        }

        let listImports: ListImports = {
            try await fileStore.listImports()
        }

        let removeImport: RemoveImport = { key in
            try await fileStore.removeImport(key)
        }

        let importUploadSource: ImportUploadSource = { key in
            try await fileStore.importUploadSource(key)
        }

        let prepareDownloadTarget: PrepareDownloadTarget = { key in
            try await fileStore.prepareDownloadTarget(key)
        }

        let downloadOffset: DownloadOffset = { key in
            try await fileStore.downloadOffset(key)
        }

        let writeDownload: WriteDownload = { key, data, offset in
            try await fileStore.writeDownload(key, data, offset)
        }

        return MediaContentStorageClient(
            storeImport: storeImport,
            listImports: listImports,
            removeImport: removeImport,
            importUploadSource: importUploadSource,
            prepareDownloadTarget: prepareDownloadTarget,
            downloadOffset: downloadOffset,
            writeDownload: writeDownload
        )
    }
}
