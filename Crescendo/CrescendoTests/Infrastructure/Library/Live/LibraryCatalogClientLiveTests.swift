import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import Crescendo

/// Proves typed catalog persistence through the shared actor-backed store.
struct LibraryCatalogClientLiveTests {
    @Test
    func missingCatalogLoadsAnEmptySnapshot() async {
        let client = makeClient(initialData: nil)

        let result = await client.load()
        let expectedSnapshot = LibraryCatalogClient.Snapshot(entries: [])

        #expect(result == .success(expectedSnapshot))
    }

    @Test
    func replacementCanBeLoadedWithoutLosingContractValues() async throws {
        let bytes = LockIsolated<Data?>(nil)
        let client = makeClient(bytes: bytes)
        let snapshot = makeSnapshot()

        let replaced = await client.replace(snapshot)
        let loaded = await client.load()

        #expect(replaced == .success(snapshot))
        #expect(loaded == .success(snapshot))
        #expect(try #require(bytes.value).contains(Data("\"version\":1".utf8)))
    }

    @Test
    func corruptCatalogMapsToCatalogReadFailure() async {
        let client = makeClient(initialData: Data("not json".utf8))

        let result = await client.load()

        #expect(result == .failure(.catalogReadFailed))
    }

    @Test
    func unsupportedCatalogVersionMapsToCatalogReadFailure() async throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["version": 2, "records": []]
        )
        let client = makeClient(initialData: data)

        let result = await client.load()

        #expect(result == .failure(.catalogReadFailed))
    }

    @Test
    func failedReplacementPreservesTheLastStoredCatalog() async {
        let bytes = LockIsolated<Data?>(nil)
        let successfulClient = makeClient(bytes: bytes)
        let snapshot = makeSnapshot()
        _ = await successfulClient.replace(snapshot)
        let failingStore = LibraryCatalogStore(
            catalogURL: URL(fileURLWithPath: "/catalog.json"),
            catalogFile: LibraryCatalogFileClient(
                read: { _ in .success(bytes.value) },
                write: { _, _ in .failure(.catalogWriteFailed) }
            )
        )
        let failingClient = LibraryCatalogClient.live(store: failingStore)

        let result = await failingClient.replace(
            LibraryCatalogClient.Snapshot(entries: [])
        )
        let preserved = await successfulClient.load()

        #expect(result == .failure(.catalogWriteFailed))
        #expect(preserved == .success(snapshot))
    }

    private func makeClient(
        initialData: Data?
    ) -> LibraryCatalogClient {
        makeClient(bytes: LockIsolated(initialData))
    }

    private func makeClient(
        bytes: LockIsolated<Data?>
    ) -> LibraryCatalogClient {
        let store = LibraryCatalogStore(
            catalogURL: URL(fileURLWithPath: "/catalog.json"),
            catalogFile: LibraryCatalogFileClient(
                read: { _ in .success(bytes.value) },
                write: { data, _ in
                    bytes.setValue(data)
                    return .success(())
                }
            )
        )
        return LibraryCatalogClient.live(store: store)
    }

    private func makeSnapshot() -> LibraryCatalogClient.Snapshot {
        let entry = LibraryCatalogClient.Entry(
            id: TrackID(
                providerID: .library,
                nativeID: "01234567-89AB-CDEF-0123-456789ABCDEF"
            ),
            audioReference: .init(
                rawValue: "Audio/01234567-89AB-CDEF-0123-456789ABCDEF.m4a"
            ),
            contentIdentity: .init(
                rawValue: String(repeating: "a", count: 64)
            ),
            title: "Song",
            artistName: "Artist",
            albumTitle: "Album",
            albumArtistName: "Album Artist",
            duration: 180,
            trackNumber: 2,
            discNumber: 1,
            artworkReference: .init(
                rawValue: "Artwork/01234567-89AB-CDEF-0123-456789ABCDEF"
            ),
            addedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        return LibraryCatalogClient.Snapshot(
            entries: IdentifiedArray(uniqueElements: [entry])
        )
    }
}
