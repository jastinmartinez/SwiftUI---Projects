import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct LibraryRecoveryReducerTests {
    @Test
    func emptyRecoveryAdvancesThroughExplicitActions() async {
        let snapshot = LibraryCatalogClient.Snapshot(entries: [])
        let library = Library(items: [])
        let store = TestStore(
            initialState: LibraryRecoveryReducer.State(
                catalog: .success(snapshot),
                storedAudio: []
            )
        ) {
            LibraryRecoveryReducer()
        }

        await store.send(.start)
        await store.receive(.nextStepRequested) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    library,
                    catalogWriteFailure: nil
                )
            )
        )
    }

    @Test
    func catalogEntryRecoveryIsPerformedByItemChild() async {
        let trackID = TrackID(
            providerID: .library,
            nativeID: "01234567-89AB-CDEF-0123-456789ABCDEF"
        )
        let audioReference = LibraryMediaStoreClient.FileReference(
            rawValue: "Audio/01234567-89AB-CDEF-0123-456789ABCDEF.m4a"
        )
        let audioURL = URL(
            fileURLWithPath:
                "/managed/Audio/01234567-89AB-CDEF-0123-456789ABCDEF.m4a"
        )
        let contentIdentity = Library.ContentIdentity(
            rawValue: String(repeating: "a", count: 64)
        )
        let addedAt = Date(timeIntervalSinceReferenceDate: 100)
        let storedAudio = LibraryMediaStoreClient.StoredAudio(
            trackID: trackID,
            reference: audioReference,
            url: audioURL,
            creationDate: Date(timeIntervalSinceReferenceDate: 200)
        )
        let catalogEntry = LibraryCatalogClient.Entry(
            id: trackID,
            audioReference: audioReference,
            contentIdentity: contentIdentity,
            title: "Catalog Song",
            artistName: "Catalog Artist",
            albumTitle: "Catalog Album",
            albumArtistName: "Catalog Album Artist",
            duration: 30,
            trackNumber: 1,
            discNumber: 1,
            artworkReference: nil,
            addedAt: addedAt
        )
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: catalogEntry,
            libraryItem: Library.Item(
                track: Track(
                    id: trackID,
                    title: "Catalog Song",
                    artistName: "Catalog Artist",
                    albumTitle: "Catalog Album",
                    artworkURL: nil,
                    duration: 30,
                    playbackURL: audioURL
                ),
                contentIdentity: contentIdentity,
                addedAt: addedAt
            )
        )
        let snapshot = LibraryCatalogClient.Snapshot(entries: [catalogEntry])
        let library = Library(items: [recoveredItem.libraryItem])
        let itemState = LibraryItemRecoveryReducer.State(
            source: .catalogEntry(
                catalogEntry,
                storedAudio: storedAudio
            )
        )
        let store = TestStore(
            initialState: LibraryRecoveryReducer.State(
                catalog: .success(snapshot),
                storedAudio: [storedAudio]
            )
        ) {
            LibraryRecoveryReducer()
        }

        await store.send(.start)
        await store.receive(.nextStepRequested) {
            $0.pendingCatalogEntries = []
            $0.unmatchedStoredAudio = []
            $0.itemRecovery = itemState
        }
        await store.receive(.itemRecovery(.start)) {
            $0.itemRecovery?.phase = .completed
        }
        await store.receive(
            .itemRecovery(
                .delegate(
                    .completed(
                        .catalogUnchanged(recoveredItem)
                    )
                )
            )
        ) {
            $0.itemRecovery = nil
            $0.recoveredItems = [recoveredItem]
        }
        await store.receive(.nextStepRequested) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    library,
                    catalogWriteFailure: nil
                )
            )
        )
    }
}
