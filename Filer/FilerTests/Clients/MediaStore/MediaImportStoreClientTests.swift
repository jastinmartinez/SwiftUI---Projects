@testable import Filer
import Foundation
import Testing

@Suite struct MediaImportStoreClientTests {
    @Test func storeWritesPayloadThroughContentStorageAndReturnsImportedMedia() async throws {
        let storedImports = LockedBox<[(key: String, data: Data)]>([])
        let contentStorage = MediaContentStorageClient(
            storeImport: { key, data in
                storedImports.mutate { $0.append((key: key, data: data)) }
                return MediaContentStorageClient.StoredContent(
                    key: key,
                    size: Int64(data.count),
                    modifiedAt: nil,
                    localURL: URL(fileURLWithPath: "/memory/imports/\(key)")
                )
            }
        )
        let client = MediaImportStoreClient.live(contentStorage: contentStorage)

        let media = try await client.store(payload())

        #expect(storedImports.value.map(\.key) == ["abc.jpeg"])
        #expect(storedImports.value.map(\.data) == [Data([1, 2, 3])])
        #expect(media.id == "abc.jpeg")
        #expect(media.name == "Photo")
        #expect(media.fileURL == URL(fileURLWithPath: "/memory/imports/abc.jpeg"))
        #expect(media.contentType == "image/jpeg")
        #expect(media.kind == .image)
        #expect(media.size == 3)
    }

    @Test func storeDoesNotRemoveExpiredImports() async throws {
        let removedKeys = LockedBox<[String]>([])
        let contentStorage = MediaContentStorageClient(
            storeImport: { key, data in
                MediaContentStorageClient.StoredContent(
                    key: key,
                    size: Int64(data.count),
                    modifiedAt: nil,
                    localURL: URL(fileURLWithPath: "/memory/imports/\(key)")
                )
            },
            listImports: {
                [Self.stored("expired.jpeg", modifiedAt: Date(timeIntervalSince1970: 0))]
            },
            removeImport: { key in removedKeys.mutate { $0.append(key) } }
        )
        let client = MediaImportStoreClient.live(
            contentStorage: contentStorage,
            now: { Date(timeIntervalSince1970: 86400 * 3) }
        )

        _ = try await client.store(payload("new.jpeg"))

        #expect(removedKeys.value.isEmpty)
    }

    @Test func removeExpiredRemovesOnlyExpiredImports() async throws {
        let now = Date(timeIntervalSince1970: 86400 * 3)
        let removedKeys = LockedBox<[String]>([])
        let contentStorage = MediaContentStorageClient(
            listImports: {
                [
                    Self.stored("expired.jpeg", modifiedAt: now.addingTimeInterval(-86401)),
                    Self.stored("fresh.jpeg", modifiedAt: now.addingTimeInterval(-86400)),
                    Self.stored("undated.jpeg", modifiedAt: nil),
                ]
            },
            removeImport: { key in removedKeys.mutate { $0.append(key) } }
        )
        let client = MediaImportStoreClient.live(contentStorage: contentStorage, now: { now })

        try await client.removeExpired()

        #expect(removedKeys.value == ["expired.jpeg"])
    }

    // MARK: - Helpers

    private func payload(_ id: String = "abc.jpeg", data: Data = Data([1, 2, 3])) -> MediaImportPayload {
        MediaImportPayload(
            id: id,
            name: "Photo",
            data: data,
            contentType: "image/jpeg",
            kind: .image
        )
    }

    private static func stored(
        _ key: String,
        modifiedAt: Date?
    ) -> MediaContentStorageClient.StoredContent {
        MediaContentStorageClient.StoredContent(
            key: key,
            size: 1,
            modifiedAt: modifiedAt,
            localURL: URL(fileURLWithPath: "/memory/imports/\(key)")
        )
    }
}
