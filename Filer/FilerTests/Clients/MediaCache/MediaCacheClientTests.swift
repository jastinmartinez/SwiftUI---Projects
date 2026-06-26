@testable import Filer
import Foundation
import Testing

@Suite struct MediaCacheClientTests {
    @Test func storeWritesPayloadThroughObjectStoreAndReturnsImportedMedia() async throws {
        let now = Date(timeIntervalSince1970: 100)
        let storedObjects = LockedBox<[ObjectStoreWrite]>([])
        let stored = StoredObject(
            id: "abc.jpeg",
            size: 3,
            modifiedAt: now,
            location: .file(URL(fileURLWithPath: "/memory/abc.jpeg"))
        )
        let client = MediaCacheClient.live(
            objectStore: ObjectStoreClient(
                put: { object in
                    storedObjects.mutate { $0.append(object) }
                    return stored
                },
                list: { [] },
                remove: { _ in }
            ),
            now: { now }
        )

        let media = try await client.store(payload())

        #expect(storedObjects.value == [ObjectStoreWrite(id: "abc.jpeg", data: Data([1, 2, 3]))])
        #expect(media.id == "abc.jpeg")
        #expect(media.name == "Photo")
        #expect(media.fileURL == URL(fileURLWithPath: "/memory/abc.jpeg"))
        #expect(media.contentType == "image/jpeg")
        #expect(media.kind == .image)
        #expect(media.size == 3)
    }

    @Test func storeRemovesExpiredObjectsAndPreservesFreshObjects() async throws {
        let now = Date(timeIntervalSince1970: 86400 * 3)
        let old = StoredObject(
            id: "old.jpeg",
            size: 1,
            modifiedAt: now.addingTimeInterval(-86401),
            location: .file(URL(fileURLWithPath: "/memory/old.jpeg"))
        )
        let fresh = StoredObject(
            id: "fresh.jpeg",
            size: 1,
            modifiedAt: now.addingTimeInterval(-3600),
            location: .file(URL(fileURLWithPath: "/memory/fresh.jpeg"))
        )
        let removedIDs = LockedBox<[String]>([])
        let storedObjects = LockedBox<[ObjectStoreWrite]>([])

        let client = MediaCacheClient.live(
            objectStore: ObjectStoreClient(
                put: { object in
                    storedObjects.mutate { $0.append(object) }
                    return StoredObject(
                        id: object.id,
                        size: Int64(object.data.count),
                        modifiedAt: now,
                        location: .file(URL(fileURLWithPath: "/memory/\(object.id)"))
                    )
                },
                list: { [old, fresh] },
                remove: { id in removedIDs.mutate { $0.append(id) } }
            ),
            now: { now }
        )

        let media = try await client.store(payload("new.jpeg"))

        #expect(removedIDs.value == ["old.jpeg"])
        #expect(removedIDs.value.contains("fresh.jpeg") == false)
        #expect(storedObjects.value == [ObjectStoreWrite(id: "new.jpeg", data: Data([1, 2, 3]))])
        #expect(media.fileURL == URL(fileURLWithPath: "/memory/new.jpeg"))
    }

    @Test func removeExpiredRemovesOnlyExpiredObjects() async throws {
        let now = Date(timeIntervalSince1970: 86400 * 3)
        let expired = StoredObject(
            id: "expired.jpeg",
            size: 1,
            modifiedAt: now.addingTimeInterval(-86401),
            location: .file(URL(fileURLWithPath: "/memory/expired.jpeg"))
        )
        let fresh = StoredObject(
            id: "fresh.jpeg",
            size: 1,
            modifiedAt: now.addingTimeInterval(-86400),
            location: .file(URL(fileURLWithPath: "/memory/fresh.jpeg"))
        )
        let undated = StoredObject(
            id: "undated.jpeg",
            size: 1,
            modifiedAt: nil,
            location: .file(URL(fileURLWithPath: "/memory/undated.jpeg"))
        )
        let removedIDs = LockedBox<[String]>([])

        let client = MediaCacheClient.live(
            objectStore: ObjectStoreClient(
                put: { _ in Issue.record("removeExpired should not store objects"); return expired },
                list: { [expired, fresh, undated] },
                remove: { id in removedIDs.mutate { $0.append(id) } }
            ),
            now: { now }
        )

        try await client.removeExpired()

        #expect(removedIDs.value == ["expired.jpeg"])
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
}
