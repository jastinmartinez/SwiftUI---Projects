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

    private func file() -> FileItem {
        FileItem(id: "abc.jpg", name: "Photo", kind: .image, size: 12, status: .remote)
    }
}

private struct Write: Equatable {
    let key: String
    let data: Data
    let offset: UInt64
}
