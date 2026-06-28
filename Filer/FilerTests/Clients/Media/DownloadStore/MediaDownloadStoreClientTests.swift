@testable import Filer
import Foundation
import Testing

@Suite struct MediaDownloadStoreClientTests {
    @Test func prepareDownloadTargetResolvesContentStorageTargetForFileID() async throws {
        let requestedKeys = LockedBox<[String]>([])
        let contentStorage = Self.contentStorage(
            prepareDownloadTarget: { key in
                requestedKeys.mutate { $0.append(key) }
                return MediaContentStorageClient.DownloadTarget(
                    key: key,
                    localURL: URL(fileURLWithPath: "/memory/downloads/\(key)")
                )
            }
        )
        let client = MediaDownloadStoreClient.live(contentStorage: contentStorage)

        let target = try await client.prepareDownloadTarget(file())

        #expect(requestedKeys.value == ["abc.jpg"])
        #expect(target.file == file())
        #expect(target.localURL == URL(fileURLWithPath: "/memory/downloads/abc.jpg"))
    }

    @Test func makeDownloadSinkReportsPersistedOffsetAndWritesChunks() async throws {
        let offsets = LockedBox<[String: UInt64]>(["abc.jpg": 6])
        let writes = LockedBox<[Write]>([])
        let contentStorage = Self.contentStorage(
            prepareDownloadTarget: { key in
                MediaContentStorageClient.DownloadTarget(
                    key: key,
                    localURL: URL(fileURLWithPath: "/memory/downloads/\(key)")
                )
            },
            downloadOffset: { key in
                offsets.value[key] ?? 0
            },
            writeDownload: { key, data, offset in
                writes.mutate { $0.append(Write(key: key, data: data, offset: offset)) }
                offsets.mutate { $0[key] = offset + UInt64(data.count) }
            }
        )
        let client = MediaDownloadStoreClient.live(contentStorage: contentStorage)
        let target = try await client.prepareDownloadTarget(file())
        let sink = client.makeDownloadSink(target)

        #expect(try await sink.currentOffset() == 6)
        try await sink.write(Data([1, 2, 3]), 6)
        #expect(try await sink.currentOffset() == 9)
        #expect(writes.value == [Write(key: "abc.jpg", data: Data([1, 2, 3]), offset: 6)])
    }

    // MARK: - Helpers

    private func file() -> FileItem {
        FileItem(
            metadata: MediaMetadata(
                id: "abc.jpg",
                name: "Photo",
                contentType: "image/jpeg",
                kind: .image,
                size: 12
            ),
            status: .remote
        )
    }

    private static func contentStorage(
        prepareDownloadTarget: @escaping MediaContentStorageClient.PrepareDownloadTarget
    ) -> MediaContentStorageClient {
        contentStorage(
            prepareDownloadTarget: prepareDownloadTarget,
            downloadOffset: { _ in throw MediaContentStorageClient.Unimplemented() },
            writeDownload: { _, _, _ in throw MediaContentStorageClient.Unimplemented() }
        )
    }

    private static func contentStorage(
        prepareDownloadTarget: @escaping MediaContentStorageClient.PrepareDownloadTarget,
        downloadOffset: @escaping MediaContentStorageClient.DownloadOffset,
        writeDownload: @escaping MediaContentStorageClient.WriteDownload
    ) -> MediaContentStorageClient {
        MediaContentStorageClient(
            storeImport: { _, _ in throw MediaContentStorageClient.Unimplemented() },
            listImports: { throw MediaContentStorageClient.Unimplemented() },
            removeImport: { _ in throw MediaContentStorageClient.Unimplemented() },
            importUploadSource: { _ in throw MediaContentStorageClient.Unimplemented() },
            prepareDownloadTarget: prepareDownloadTarget,
            downloadOffset: downloadOffset,
            writeDownload: writeDownload
        )
    }
}

// MARK: - Helpers

private struct Write: Equatable {
    let key: String
    let data: Data
    let offset: UInt64
}
