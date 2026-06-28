@testable import Filer
import Foundation
import Testing

@Suite struct MediaDownloadStoreClientTests {
    @Test func downloadTargetResolvesContentStorageTargetForFileID() async throws {
        let requestedKeys = LockedBox<[String]>([])
        let contentStorage = MediaContentStorageClient(
            prepareDownloadTarget: { key in
                requestedKeys.mutate { $0.append(key) }
                return MediaContentStorageClient.DownloadTarget(
                    key: key,
                    localURL: URL(fileURLWithPath: "/memory/downloads/\(key)")
                )
            }
        )
        let client = MediaDownloadStoreClient.live(contentStorage: contentStorage)

        let target = try await client.downloadTarget(file())

        #expect(requestedKeys.value == ["abc.jpg"])
        #expect(target.file == file())
        #expect(target.localURL == URL(fileURLWithPath: "/memory/downloads/abc.jpg"))
    }

    @Test func writeDownloadChunkWritesToContentStorageTargetKey() async throws {
        let writes = LockedBox<[Write]>([])
        let contentStorage = MediaContentStorageClient(
            writeDownload: { key, data, offset in
                writes.mutate { $0.append(Write(key: key, data: data, offset: offset)) }
            }
        )
        let client = MediaDownloadStoreClient.live(contentStorage: contentStorage)
        let target = MediaDownloadStoreClient.Target(
            file: file(),
            key: "abc.jpg",
            localURL: URL(fileURLWithPath: "/memory/downloads/abc.jpg")
        )

        try await client.writeDownloadChunk(target, Data([1, 2]), 6)

        #expect(writes.value == [Write(key: "abc.jpg", data: Data([1, 2]), offset: 6)])
    }

    @Test func downloadSinkReportsPersistedOffsetAndWritesChunks() async throws {
        let offsets = LockedBox<[String: UInt64]>(["abc.jpg": 6])
        let writes = LockedBox<[Write]>([])
        let contentStorage = MediaContentStorageClient(
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
        let target = try await client.downloadTarget(file())
        let sink = client.downloadSink(target)

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
}

// MARK: - Helpers

private struct Write: Equatable {
    let key: String
    let data: Data
    let offset: UInt64
}
