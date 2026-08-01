import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct LibraryItemRecoveryReducerTests {
    @Test
    func catalogEntryWithoutArtworkCompletesWithoutCatalogChange() async {
        let fixture = Fixture()
        let catalogEntry = fixture.catalogEntry()
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: catalogEntry,
            libraryItem: fixture.libraryItem()
        )
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .catalogEntry(
                    catalogEntry,
                    storedAudio: fixture.storedAudio
                )
            )
        ) {
            LibraryItemRecoveryReducer()
        }

        await store.send(.start) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogUnchanged(recoveredItem)
                )
            )
        )
    }

    @Test
    func availableCatalogArtworkCompletesWithoutCatalogChange() async {
        let fixture = Fixture()
        let artworkReference = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/01234567-89AB-CDEF-0123-456789ABCDEF.jpg"
        )
        let artworkURL = URL(
            fileURLWithPath:
                "/managed/Artwork/01234567-89AB-CDEF-0123-456789ABCDEF.jpg"
        )
        let catalogEntry = fixture.catalogEntry(
            artworkReference: artworkReference
        )
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: catalogEntry,
            libraryItem: fixture.libraryItem(artworkURL: artworkURL)
        )
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.resolveFileURL = { reference in
            guard reference == artworkReference else {
                return .failure(.invalidManagedFile)
            }
            return .success(artworkURL)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .catalogEntry(
                    catalogEntry,
                    storedAudio: fixture.storedAudio
                )
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
        }

        await store.send(.start) {
            $0.phase = .resolvingArtwork(
                catalogEntry,
                fixture.storedAudio
            )
        }
        await store.receive(
            .artworkResolutionCompleted(.success(artworkURL))
        ) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogUnchanged(recoveredItem)
                )
            )
        )
    }

    @Test
    func unavailableCatalogArtworkIsRecoveredAndChangesCatalog() async {
        let fixture = Fixture()
        let missingArtworkReference = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/missing.jpg"
        )
        let recoveredArtworkReference = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/01234567-89AB-CDEF-0123-456789ABCDEF.jpg"
        )
        let recoveredArtworkURL = URL(
            fileURLWithPath:
                "/managed/Artwork/01234567-89AB-CDEF-0123-456789ABCDEF.jpg"
        )
        let artworkData = Data([0x01, 0x02, 0x03])
        let catalogEntry = fixture.catalogEntry(
            artworkReference: missingArtworkReference
        )
        let entryWithoutArtwork = fixture.catalogEntry()
        let recoveredCatalogEntry = fixture.catalogEntry(
            artworkReference: recoveredArtworkReference
        )
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: recoveredCatalogEntry,
            libraryItem: fixture.libraryItem(
                artworkURL: recoveredArtworkURL
            )
        )
        let metadata = fixture.metadata(artworkData: artworkData)
        let storedArtwork = LibraryMediaStoreClient.StoredArtwork(
            reference: recoveredArtworkReference,
            url: recoveredArtworkURL
        )
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.resolveFileURL = { _ in
            .failure(.invalidManagedFile)
        }
        mediaStore.storeArtwork = { data, trackID in
            guard data == artworkData, trackID == fixture.trackID else {
                return .failure(.fileWriteFailed)
            }
            return .success(storedArtwork)
        }
        let metadataClient = AudioMetadataClient { url in
            guard url == fixture.audioURL else {
                return .failure(.metadataReadFailed)
            }
            return .success(metadata)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .catalogEntry(
                    catalogEntry,
                    storedAudio: fixture.storedAudio
                )
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
            $0.audioMetadata = metadataClient
        }

        await store.send(.start) {
            $0.phase = .resolvingArtwork(
                catalogEntry,
                fixture.storedAudio
            )
        }
        await store.receive(
            .artworkResolutionCompleted(.failure(.invalidManagedFile))
        ) {
            $0.phase = .readingMissingArtwork(
                entryWithoutArtwork,
                fixture.storedAudio
            )
        }
        await store.receive(.missingArtworkMetadataRead(.success(metadata))) {
            $0.phase = .storingRecoveredArtwork(
                entryWithoutArtwork,
                fixture.storedAudio
            )
        }
        await store.receive(
            .recoveredArtworkStorageCompleted(.success(storedArtwork))
        ) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogChanged(recoveredItem)
                )
            )
        )
    }

    @Test
    func unavailableArtworkWithoutEmbeddedReplacementStillRecoversItem() async {
        let fixture = Fixture()
        let missingArtworkReference = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/missing.jpg"
        )
        let catalogEntry = fixture.catalogEntry(
            artworkReference: missingArtworkReference
        )
        let entryWithoutArtwork = fixture.catalogEntry()
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: entryWithoutArtwork,
            libraryItem: fixture.libraryItem()
        )
        let metadata = fixture.metadata(artworkData: nil)
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.resolveFileURL = { _ in
            .failure(.invalidManagedFile)
        }
        let metadataClient = AudioMetadataClient { _ in
            .success(metadata)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .catalogEntry(
                    catalogEntry,
                    storedAudio: fixture.storedAudio
                )
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
            $0.audioMetadata = metadataClient
        }

        await store.send(.start) {
            $0.phase = .resolvingArtwork(
                catalogEntry,
                fixture.storedAudio
            )
        }
        await store.receive(
            .artworkResolutionCompleted(.failure(.invalidManagedFile))
        ) {
            $0.phase = .readingMissingArtwork(
                entryWithoutArtwork,
                fixture.storedAudio
            )
        }
        await store.receive(.missingArtworkMetadataRead(.success(metadata))) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogChanged(recoveredItem)
                )
            )
        )
    }

    @Test
    func unavailableArtworkWithUnreadableMetadataStillRecoversItem() async {
        let fixture = Fixture()
        let missingArtworkReference = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/missing.jpg"
        )
        let catalogEntry = fixture.catalogEntry(
            artworkReference: missingArtworkReference
        )
        let entryWithoutArtwork = fixture.catalogEntry()
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: entryWithoutArtwork,
            libraryItem: fixture.libraryItem()
        )
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.resolveFileURL = { _ in
            .failure(.invalidManagedFile)
        }
        let metadataClient = AudioMetadataClient { _ in
            .failure(.metadataReadFailed)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .catalogEntry(
                    catalogEntry,
                    storedAudio: fixture.storedAudio
                )
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
            $0.audioMetadata = metadataClient
        }

        await store.send(.start) {
            $0.phase = .resolvingArtwork(
                catalogEntry,
                fixture.storedAudio
            )
        }
        await store.receive(
            .artworkResolutionCompleted(.failure(.invalidManagedFile))
        ) {
            $0.phase = .readingMissingArtwork(
                entryWithoutArtwork,
                fixture.storedAudio
            )
        }
        await store.receive(
            .missingArtworkMetadataRead(.failure(.metadataReadFailed))
        ) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogChanged(recoveredItem)
                )
            )
        )
    }

    @Test
    func failedRecoveredArtworkStorageStillRecoversItem() async {
        let fixture = Fixture()
        let missingArtworkReference = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/missing.jpg"
        )
        let artworkData = Data([0x01, 0x02, 0x03])
        let catalogEntry = fixture.catalogEntry(
            artworkReference: missingArtworkReference
        )
        let entryWithoutArtwork = fixture.catalogEntry()
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: entryWithoutArtwork,
            libraryItem: fixture.libraryItem()
        )
        let metadata = fixture.metadata(artworkData: artworkData)
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.resolveFileURL = { _ in
            .failure(.invalidManagedFile)
        }
        mediaStore.storeArtwork = { _, _ in
            .failure(.fileWriteFailed)
        }
        let metadataClient = AudioMetadataClient { _ in
            .success(metadata)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .catalogEntry(
                    catalogEntry,
                    storedAudio: fixture.storedAudio
                )
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
            $0.audioMetadata = metadataClient
        }

        await store.send(.start) {
            $0.phase = .resolvingArtwork(
                catalogEntry,
                fixture.storedAudio
            )
        }
        await store.receive(
            .artworkResolutionCompleted(.failure(.invalidManagedFile))
        ) {
            $0.phase = .readingMissingArtwork(
                entryWithoutArtwork,
                fixture.storedAudio
            )
        }
        await store.receive(.missingArtworkMetadataRead(.success(metadata))) {
            $0.phase = .storingRecoveredArtwork(
                entryWithoutArtwork,
                fixture.storedAudio
            )
        }
        await store.receive(
            .recoveredArtworkStorageCompleted(.failure(.fileWriteFailed))
        ) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogChanged(recoveredItem)
                )
            )
        )
    }

    @Test
    func uncatalogedAudioIsIdentifiedAndRecoveredFromMetadata() async {
        let fixture = Fixture()
        let metadata = fixture.metadata(artworkData: nil)
        let recoveredEntry = LibraryCatalogClient.Entry(
            id: fixture.trackID,
            audioReference: fixture.audioReference,
            contentIdentity: fixture.contentIdentity,
            title: "Catalog Song",
            artistName: "Catalog Artist",
            albumTitle: "Catalog Album",
            albumArtistName: "Catalog Album Artist",
            duration: 30,
            trackNumber: 1,
            discNumber: 1,
            artworkReference: nil,
            addedAt: fixture.storedAudio.creationDate
        )
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: recoveredEntry,
            libraryItem: Library.Item(
                track: Track(
                    id: fixture.trackID,
                    title: "Catalog Song",
                    artistName: "Catalog Artist",
                    albumTitle: "Catalog Album",
                    artworkURL: nil,
                    duration: 30,
                    playbackURL: fixture.audioURL
                ),
                contentIdentity: fixture.contentIdentity,
                addedAt: fixture.storedAudio.creationDate
            )
        )
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.identifyAudio = { url in
            guard url == fixture.audioURL else {
                return .failure(.fileReadFailed)
            }
            return .success(fixture.contentIdentity)
        }
        let metadataClient = AudioMetadataClient { url in
            guard url == fixture.audioURL else {
                return .failure(.metadataReadFailed)
            }
            return .success(metadata)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .uncatalogedAudio(fixture.storedAudio)
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
            $0.audioMetadata = metadataClient
        }

        await store.send(.start) {
            $0.phase = .identifyingAudio(fixture.storedAudio)
        }
        await store.receive(
            .audioIdentificationCompleted(
                .success(fixture.contentIdentity)
            )
        ) {
            $0.phase = .readingMetadata(
                fixture.storedAudio,
                fixture.contentIdentity
            )
        }
        await store.receive(.audioMetadataRead(.success(metadata))) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogChanged(recoveredItem)
                )
            )
        )
    }

    @Test
    func uncatalogedAudioStoresEmbeddedArtwork() async {
        let fixture = Fixture()
        let artworkData = Data([0x01, 0x02, 0x03])
        let metadata = fixture.metadata(artworkData: artworkData)
        let artworkReference = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/01234567-89AB-CDEF-0123-456789ABCDEF.jpg"
        )
        let artworkURL = URL(
            fileURLWithPath:
                "/managed/Artwork/01234567-89AB-CDEF-0123-456789ABCDEF.jpg"
        )
        let storedArtwork = LibraryMediaStoreClient.StoredArtwork(
            reference: artworkReference,
            url: artworkURL
        )
        let recoveredEntry = LibraryCatalogClient.Entry(
            id: fixture.trackID,
            audioReference: fixture.audioReference,
            contentIdentity: fixture.contentIdentity,
            title: "Catalog Song",
            artistName: "Catalog Artist",
            albumTitle: "Catalog Album",
            albumArtistName: "Catalog Album Artist",
            duration: 30,
            trackNumber: 1,
            discNumber: 1,
            artworkReference: artworkReference,
            addedAt: fixture.storedAudio.creationDate
        )
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: recoveredEntry,
            libraryItem: Library.Item(
                track: Track(
                    id: fixture.trackID,
                    title: "Catalog Song",
                    artistName: "Catalog Artist",
                    albumTitle: "Catalog Album",
                    artworkURL: artworkURL,
                    duration: 30,
                    playbackURL: fixture.audioURL
                ),
                contentIdentity: fixture.contentIdentity,
                addedAt: fixture.storedAudio.creationDate
            )
        )
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.identifyAudio = { _ in
            .success(fixture.contentIdentity)
        }
        mediaStore.storeArtwork = { data, trackID in
            guard data == artworkData, trackID == fixture.trackID else {
                return .failure(.fileWriteFailed)
            }
            return .success(storedArtwork)
        }
        let metadataClient = AudioMetadataClient { _ in
            .success(metadata)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .uncatalogedAudio(fixture.storedAudio)
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
            $0.audioMetadata = metadataClient
        }

        await store.send(.start) {
            $0.phase = .identifyingAudio(fixture.storedAudio)
        }
        await store.receive(
            .audioIdentificationCompleted(
                .success(fixture.contentIdentity)
            )
        ) {
            $0.phase = .readingMetadata(
                fixture.storedAudio,
                fixture.contentIdentity
            )
        }
        await store.receive(.audioMetadataRead(.success(metadata))) {
            $0.phase = .storingNewArtwork(
                fixture.storedAudio,
                fixture.contentIdentity,
                metadata
            )
        }
        await store.receive(
            .newArtworkStorageCompleted(.success(storedArtwork))
        ) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogChanged(recoveredItem)
                )
            )
        )
    }

    @Test
    func uncatalogedAudioIdentificationFailureIsTerminal() async {
        let fixture = Fixture()
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.identifyAudio = { _ in
            .failure(.fileReadFailed)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .uncatalogedAudio(fixture.storedAudio)
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
        }

        await store.send(.start) {
            $0.phase = .identifyingAudio(fixture.storedAudio)
        }
        await store.receive(
            .audioIdentificationCompleted(.failure(.fileReadFailed))
        ) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(.failed(.fileReadFailed))
        )
    }

    @Test
    func uncatalogedAudioMetadataFailureIsTerminal() async {
        let fixture = Fixture()
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.identifyAudio = { _ in
            .success(fixture.contentIdentity)
        }
        let metadataClient = AudioMetadataClient { _ in
            .failure(.metadataReadFailed)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .uncatalogedAudio(fixture.storedAudio)
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
            $0.audioMetadata = metadataClient
        }

        await store.send(.start) {
            $0.phase = .identifyingAudio(fixture.storedAudio)
        }
        await store.receive(
            .audioIdentificationCompleted(
                .success(fixture.contentIdentity)
            )
        ) {
            $0.phase = .readingMetadata(
                fixture.storedAudio,
                fixture.contentIdentity
            )
        }
        await store.receive(
            .audioMetadataRead(.failure(.metadataReadFailed))
        ) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(.failed(.metadataReadFailed))
        )
    }

    @Test
    func uncatalogedAudioArtworkStorageFailureStillRecoversItem() async {
        let fixture = Fixture()
        let artworkData = Data([0x01, 0x02, 0x03])
        let metadata = fixture.metadata(artworkData: artworkData)
        let recoveredEntry = LibraryCatalogClient.Entry(
            id: fixture.trackID,
            audioReference: fixture.audioReference,
            contentIdentity: fixture.contentIdentity,
            title: "Catalog Song",
            artistName: "Catalog Artist",
            albumTitle: "Catalog Album",
            albumArtistName: "Catalog Album Artist",
            duration: 30,
            trackNumber: 1,
            discNumber: 1,
            artworkReference: nil,
            addedAt: fixture.storedAudio.creationDate
        )
        let recoveredItem = LibraryItemRecoveryReducer.RecoveredItem(
            catalogEntry: recoveredEntry,
            libraryItem: Library.Item(
                track: Track(
                    id: fixture.trackID,
                    title: "Catalog Song",
                    artistName: "Catalog Artist",
                    albumTitle: "Catalog Album",
                    artworkURL: nil,
                    duration: 30,
                    playbackURL: fixture.audioURL
                ),
                contentIdentity: fixture.contentIdentity,
                addedAt: fixture.storedAudio.creationDate
            )
        )
        var mediaStore = LibraryMediaStoreClient.liveValue
        mediaStore.identifyAudio = { _ in
            .success(fixture.contentIdentity)
        }
        mediaStore.storeArtwork = { _, _ in
            .failure(.fileWriteFailed)
        }
        let metadataClient = AudioMetadataClient { _ in
            .success(metadata)
        }
        let store = TestStore(
            initialState: LibraryItemRecoveryReducer.State(
                source: .uncatalogedAudio(fixture.storedAudio)
            )
        ) {
            LibraryItemRecoveryReducer()
        } withDependencies: {
            $0.libraryMediaStore = mediaStore
            $0.audioMetadata = metadataClient
        }

        await store.send(.start) {
            $0.phase = .identifyingAudio(fixture.storedAudio)
        }
        await store.receive(
            .audioIdentificationCompleted(
                .success(fixture.contentIdentity)
            )
        ) {
            $0.phase = .readingMetadata(
                fixture.storedAudio,
                fixture.contentIdentity
            )
        }
        await store.receive(.audioMetadataRead(.success(metadata))) {
            $0.phase = .storingNewArtwork(
                fixture.storedAudio,
                fixture.contentIdentity,
                metadata
            )
        }
        await store.receive(
            .newArtworkStorageCompleted(.failure(.fileWriteFailed))
        ) {
            $0.phase = .completed
        }
        await store.receive(
            .delegate(
                .completed(
                    .catalogChanged(recoveredItem)
                )
            )
        )
    }
}

private extension LibraryItemRecoveryReducerTests {
    struct Fixture {
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

        var storedAudio: LibraryMediaStoreClient.StoredAudio {
            LibraryMediaStoreClient.StoredAudio(
                trackID: trackID,
                reference: audioReference,
                url: audioURL,
                creationDate: Date(timeIntervalSinceReferenceDate: 200)
            )
        }

        func catalogEntry(
            artworkReference: LibraryMediaStoreClient.FileReference? = nil
        ) -> LibraryCatalogClient.Entry {
            LibraryCatalogClient.Entry(
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
                artworkReference: artworkReference,
                addedAt: addedAt
            )
        }

        func libraryItem(artworkURL: URL? = nil) -> Library.Item {
            Library.Item(
                track: Track(
                    id: trackID,
                    title: "Catalog Song",
                    artistName: "Catalog Artist",
                    albumTitle: "Catalog Album",
                    artworkURL: artworkURL,
                    duration: 30,
                    playbackURL: audioURL
                ),
                contentIdentity: contentIdentity,
                addedAt: addedAt
            )
        }

        func metadata(artworkData: Data?) -> AudioMetadataClient.Metadata {
            AudioMetadataClient.Metadata(
                title: "Catalog Song",
                artistName: "Catalog Artist",
                albumTitle: "Catalog Album",
                albumArtistName: "Catalog Album Artist",
                duration: 30,
                trackNumber: 1,
                discNumber: 1,
                artworkData: artworkData
            )
        }
    }
}
