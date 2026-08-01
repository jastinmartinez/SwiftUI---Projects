import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import Crescendo

@MainActor
struct LibraryReducerTests {
    @Test
    func importButtonPresentsFileImporter() async {
        let store = makeStore(scenario: Scenario())

        await store.send(.importButtonTapped) {
            $0.isFileImporterPresented = true
        }
        await store.send(.setFileImporterPresented(false)) {
            $0.isFileImporterPresented = false
        }
    }

    @Test
    func selectedFilesStartImportFromConfirmedProjection() async {
        let source = URL(fileURLWithPath: "/external/song.m4a")
        let storedAudio = makeStoredAudio()
        let entry = makeEntry(audioReference: storedAudio.reference)
        let catalog = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = makeLibrary(entry: entry, storedAudio: storedAudio)
        let store = makeStore(
            scenario: Scenario(),
            initialLibrary: library,
            initialCatalog: catalog
        )

        await store.send(.filesSelected([source])) {
            $0.isFileImporterPresented = false
            $0.fileSelectionFailure = nil
            $0.importBatch = LibraryImportReducer.State(
                sources: [source],
                library: library,
                catalog: catalog
            )
        }
    }

    @Test
    func completedImportCommitsConfirmedProjectionAndKeepsSummary() async {
        let storedAudio = makeStoredAudio()
        let entry = makeEntry(audioReference: storedAudio.reference)
        let catalog = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = makeLibrary(entry: entry, storedAudio: storedAudio)
        let summary = LibraryImportReducer.Summary(
            importedCount: 1,
            duplicateCount: 0,
            issues: []
        )
        var importBatch = LibraryImportReducer.State(
            sources: [],
            library: Library(items: []),
            catalog: .init(entries: [])
        )
        importBatch.lifecycle = .completed(summary)
        importBatch.phase = .completed
        let completion = LibraryImportReducer.Completion(
            library: library,
            catalog: catalog,
            summary: summary
        )
        let store = makeStore(
            scenario: Scenario(),
            initialImportBatch: importBatch
        )

        await store.send(
            .importBatch(.delegate(.completed(completion)))
        ) {
            $0.library = library
            $0.catalog = catalog
        }

        #expect(store.state.importBatch?.lifecycle == .completed(summary))
    }

    @Test
    func cancelledImportCommitsPartialConfirmedProjection() async {
        let storedAudio = makeStoredAudio()
        let entry = makeEntry(audioReference: storedAudio.reference)
        let catalog = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = makeLibrary(entry: entry, storedAudio: storedAudio)
        let summary = LibraryImportReducer.Summary(
            importedCount: 1,
            duplicateCount: 0,
            issues: []
        )
        var importBatch = LibraryImportReducer.State(
            sources: [],
            library: Library(items: []),
            catalog: .init(entries: [])
        )
        importBatch.lifecycle = .cancelled(summary)
        importBatch.phase = .completed
        let completion = LibraryImportReducer.Completion(
            library: library,
            catalog: catalog,
            summary: summary
        )
        let store = makeStore(
            scenario: Scenario(),
            initialImportBatch: importBatch
        )

        await store.send(
            .importBatch(.delegate(.cancelled(completion)))
        ) {
            $0.library = library
            $0.catalog = catalog
        }

        #expect(store.state.importBatch?.lifecycle == .cancelled(summary))
    }

    @Test
    func cancelImportRoutesToActiveBatch() async {
        let source = URL(fileURLWithPath: "/external/song.m4a")
        let importBatch = LibraryImportReducer.State(
            sources: [source],
            library: Library(items: []),
            catalog: .init(entries: [])
        )
        let store = makeStore(
            scenario: Scenario(),
            initialImportBatch: importBatch
        )

        await store.send(.cancelImportButtonTapped)
        await store.receive(.importBatch(.cancelButtonTapped)) {
            $0.importBatch?.phase = .cancellationRequested
        }
    }

    @Test
    func pickerFailureDismissesImporterAndNextAttemptClearsFailure() async {
        let store = makeStore(scenario: Scenario())

        await store.send(.importButtonTapped) {
            $0.isFileImporterPresented = true
        }
        await store.send(.fileSelectionFailed(.fileReadFailed)) {
            $0.isFileImporterPresented = false
            $0.fileSelectionFailure = .fileReadFailed
        }
        await store.send(.importButtonTapped) {
            $0.isFileImporterPresented = true
            $0.fileSelectionFailure = nil
        }
    }

    @Test
    func songsDestinationUpdatesNavigationPath() async {
        let store = makeStore(scenario: Scenario())

        await store.send(.destinationTapped(.songs)) {
            $0.path = [.songs]
        }
        await store.send(.pathChanged([])) {
            $0.path = []
        }
    }

    @Test
    func retainedTrackSelectionDelegatesFrozenLibraryOrder() async {
        let firstTrack = Track(
            id: TrackID(providerID: .library, nativeID: "first"),
            title: "First",
            artistName: nil,
            albumTitle: nil,
            artworkURL: nil,
            duration: nil,
            playbackURL: URL(fileURLWithPath: "/managed/first.m4a")
        )
        let secondTrack = Track(
            id: TrackID(providerID: .library, nativeID: "second"),
            title: "Second",
            artistName: nil,
            albumTitle: nil,
            artworkURL: nil,
            duration: nil,
            playbackURL: URL(fileURLWithPath: "/managed/second.m4a")
        )
        let library = Library(
            items: [
                Library.Item(
                    track: firstTrack,
                    contentIdentity: .init(rawValue: "first-content"),
                    addedAt: Date(timeIntervalSinceReferenceDate: 1)
                ),
                Library.Item(
                    track: secondTrack,
                    contentIdentity: .init(rawValue: "second-content"),
                    addedAt: Date(timeIntervalSinceReferenceDate: 2)
                ),
            ]
        )
        let store = makeStore(
            scenario: Scenario(),
            initialLibrary: library
        )

        await store.send(.trackTapped(secondTrack.id))
        await store.receive(
            .delegate(
                .trackTapped(
                    secondTrack,
                    loadedTracks: [firstTrack, secondTrack]
                )
            )
        )
    }

    @Test
    func missingTrackSelectionDoesNotDelegate() async {
        let store = makeStore(scenario: Scenario())

        await store.send(
            .trackTapped(
                TrackID(providerID: .library, nativeID: "missing")
            )
        )
    }

    @Test
    func emptyLoadBecomesLoadedWithoutReplacingCatalog() async {
        let scenario = Scenario()
        let store = makeStore(scenario: scenario)
        let emptySnapshot = LibraryCatalogClient.Snapshot(entries: [])
        let emptyLibrary = Library(items: [])

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(emptySnapshot),
                storedAudio: .success([])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: emptyLibrary,
                            catalog: emptySnapshot,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = emptyLibrary
            $0.catalog = emptySnapshot
            $0.loadStatus = .loaded
        }

        expectLoadCalls(scenario.calls.value)
    }

    @Test
    func loadStartsCatalogAndStoredAudioConcurrently() async {
        let emptySnapshot = LibraryCatalogClient.Snapshot(entries: [])
        let emptyLibrary = Library(items: [])
        let storedAudioStarted = LockIsolated(false)
        let catalogObservedStoredAudioStart = LockIsolated(false)
        let scenario = Scenario()
        var catalogClient = scenario.catalogClient
        catalogClient.load = {
            for _ in 0..<1_000 {
                if storedAudioStarted.value {
                    break
                }
                await Task.yield()
            }
            catalogObservedStoredAudioStart.withValue {
                $0 = storedAudioStarted.value
            }
            return .success(emptySnapshot)
        }
        var mediaStoreClient = scenario.mediaStoreClient
        mediaStoreClient.listStoredAudio = {
            storedAudioStarted.withValue { $0 = true }
            return .success([])
        }
        let store = TestStore(
            initialState: LibraryReducer.State(
                library: emptyLibrary,
                catalog: emptySnapshot,
                loadStatus: .idle,
                path: [],
                isFileImporterPresented: false,
                recovery: nil,
                importBatch: nil,
                fileSelectionFailure: nil
            )
        ) {
            LibraryReducer()
        } withDependencies: {
            $0.libraryCatalog = catalogClient
            $0.libraryMediaStore = mediaStoreClient
            $0.audioMetadata = scenario.metadataClient
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(emptySnapshot),
                storedAudio: .success([])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: emptyLibrary,
                            catalog: emptySnapshot,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = emptyLibrary
            $0.loadStatus = .loaded
        }

        #expect(catalogObservedStoredAudioStart.value)
    }

    @Test
    func validCatalogHydratesFromManagedURLWithoutRewrite() async {
        let storedAudio = makeStoredAudio()
        let entry = makeEntry(audioReference: storedAudio.reference)
        let snapshot = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = makeLibrary(entry: entry, storedAudio: storedAudio)
        let scenario = Scenario(
            catalogLoads: [.success(snapshot)],
            storedAudioLists: [.success([storedAudio])]
        )
        let store = makeStore(scenario: scenario)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(snapshot),
                storedAudio: .success([storedAudio])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: library,
                            catalog: snapshot,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = library
            $0.catalog = snapshot
            $0.loadStatus = .loaded
        }

        expectLoadCalls(scenario.calls.value)
    }

    @Test
    func staleCatalogEntryIsRemovedWithOneReplacement() async {
        let entry = makeEntry()
        let snapshot = LibraryCatalogClient.Snapshot(entries: [entry])
        let emptySnapshot = LibraryCatalogClient.Snapshot(entries: [])
        let emptyLibrary = Library(items: [])
        let scenario = Scenario(
            catalogLoads: [.success(snapshot)]
        )
        let store = makeStore(scenario: scenario)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(snapshot),
                storedAudio: .success([])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: emptyLibrary,
                            catalog: emptySnapshot,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = emptyLibrary
            $0.loadStatus = .loaded
        }

        expectLoadCalls(
            scenario.calls.value,
            followedBy: [
                .replaceCatalog(emptySnapshot)
            ]
        )
    }

    @Test
    func managedAudioMissingFromCatalogIsRecreated() async {
        let storedAudio = makeStoredAudio()
        let identity = makeContentIdentity()
        let metadata = makeMetadata()
        let entry = makeEntry(
            audioReference: storedAudio.reference,
            contentIdentity: identity,
            title: "Recovered Song",
            artistName: "Recovered Artist",
            albumTitle: "Recovered Album",
            albumArtistName: "Recovered Album Artist",
            duration: 42,
            trackNumber: 2,
            discNumber: 1,
            addedAt: storedAudio.creationDate
        )
        let replacement = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = makeLibrary(entry: entry, storedAudio: storedAudio)
        let scenario = Scenario(
            storedAudioLists: [.success([storedAudio])],
            identities: [storedAudio.url: .success(identity)],
            metadata: [storedAudio.url: .success(metadata)]
        )
        let store = makeStore(scenario: scenario)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(.init(entries: [])),
                storedAudio: .success([storedAudio])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: library,
                            catalog: replacement,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = library
            $0.loadStatus = .loaded
        }

        expectLoadCalls(
            scenario.calls.value,
            followedBy: [
                .identifyAudio(storedAudio.url),
                .readMetadata(storedAudio.url),
                .replaceCatalog(replacement),
            ]
        )
    }

    @Test(arguments: [String?.none, "   "])
    func missingMetadataTitleUsesFilenameStem(
        _ metadataTitle: String?
    ) async {
        let storedAudio = makeStoredAudio()
        let identity = makeContentIdentity()
        let metadata = makeMetadata(title: metadataTitle)
        let filenameTitle = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let entry = makeEntry(
            audioReference: storedAudio.reference,
            contentIdentity: identity,
            title: filenameTitle,
            artistName: "Recovered Artist",
            albumTitle: "Recovered Album",
            albumArtistName: "Recovered Album Artist",
            duration: 42,
            trackNumber: 2,
            discNumber: 1,
            addedAt: storedAudio.creationDate
        )
        let replacement = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = makeLibrary(entry: entry, storedAudio: storedAudio)
        let scenario = Scenario(
            storedAudioLists: [.success([storedAudio])],
            identities: [storedAudio.url: .success(identity)],
            metadata: [storedAudio.url: .success(metadata)]
        )
        let store = makeStore(scenario: scenario)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(.init(entries: [])),
                storedAudio: .success([storedAudio])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: library,
                            catalog: replacement,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = library
            $0.loadStatus = .loaded
        }

        expectLoadCalls(
            scenario.calls.value,
            followedBy: [
                .identifyAudio(storedAudio.url),
                .readMetadata(storedAudio.url),
                .replaceCatalog(replacement),
            ]
        )
    }

    @Test
    func corruptCatalogRebuildsEveryManagedAudioEntry() async {
        let storedAudio = makeStoredAudio()
        let identity = makeContentIdentity()
        let metadata = makeMetadata()
        let entry = makeEntry(
            audioReference: storedAudio.reference,
            contentIdentity: identity,
            title: "Recovered Song",
            artistName: "Recovered Artist",
            albumTitle: "Recovered Album",
            albumArtistName: "Recovered Album Artist",
            duration: 42,
            trackNumber: 2,
            discNumber: 1,
            addedAt: storedAudio.creationDate
        )
        let replacement = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = makeLibrary(entry: entry, storedAudio: storedAudio)
        let scenario = Scenario(
            catalogLoads: [.failure(.catalogReadFailed)],
            storedAudioLists: [.success([storedAudio])],
            identities: [storedAudio.url: .success(identity)],
            metadata: [storedAudio.url: .success(metadata)]
        )
        let store = makeStore(scenario: scenario)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .failure(.catalogReadFailed),
                storedAudio: .success([storedAudio])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: library,
                            catalog: replacement,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = library
            $0.loadStatus = .loaded
        }

        expectLoadCalls(
            scenario.calls.value,
            followedBy: [
                .identifyAudio(storedAudio.url),
                .readMetadata(storedAudio.url),
                .replaceCatalog(replacement),
            ]
        )
    }

    @Test
    func failedCatalogRewriteKeepsRecoveredLibraryUsable() async {
        let storedAudio = makeStoredAudio()
        let identity = makeContentIdentity()
        let metadata = makeMetadata()
        let entry = makeEntry(
            audioReference: storedAudio.reference,
            contentIdentity: identity,
            title: "Recovered Song",
            artistName: "Recovered Artist",
            albumTitle: "Recovered Album",
            albumArtistName: "Recovered Album Artist",
            duration: 42,
            trackNumber: 2,
            discNumber: 1,
            addedAt: storedAudio.creationDate
        )
        let replacement = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = makeLibrary(entry: entry, storedAudio: storedAudio)
        let scenario = Scenario(
            storedAudioLists: [.success([storedAudio])],
            catalogReplaceFailure: .catalogWriteFailed,
            identities: [storedAudio.url: .success(identity)],
            metadata: [storedAudio.url: .success(metadata)]
        )
        let store = makeStore(scenario: scenario)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(.init(entries: [])),
                storedAudio: .success([storedAudio])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: library,
                            catalog: replacement,
                            catalogWriteFailure: .catalogWriteFailed
                        )
                    )
                )
            )
        ) {
            $0.library = library
            $0.catalog = replacement
            $0.loadStatus = .recoveredWithCatalogFailure(
                .catalogWriteFailed
            )
        }

        expectLoadCalls(
            scenario.calls.value,
            followedBy: [
                .identifyAudio(storedAudio.url),
                .readMetadata(storedAudio.url),
                .replaceCatalog(replacement),
            ]
        )
    }

    @Test
    func missingArtworkIsReextractedAndCataloged() async {
        let storedAudio = makeStoredAudio()
        let missingArtwork = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/missing"
        )
        let storedArtwork = LibraryMediaStoreClient.StoredArtwork(
            reference: .init(rawValue: "Artwork/recovered"),
            url: URL(fileURLWithPath: "/managed/Artwork/recovered.jpg")
        )
        let originalEntry = makeEntry(
            audioReference: storedAudio.reference,
            artworkReference: missingArtwork
        )
        let recoveredEntry = makeEntry(
            audioReference: storedAudio.reference,
            artworkReference: storedArtwork.reference
        )
        let originalSnapshot = LibraryCatalogClient.Snapshot(
            entries: [originalEntry]
        )
        let replacement = LibraryCatalogClient.Snapshot(
            entries: [recoveredEntry]
        )
        let artworkData = Data("artwork".utf8)
        let metadata = makeMetadata(artworkData: artworkData)
        let library = makeLibrary(
            entry: recoveredEntry,
            storedAudio: storedAudio,
            artworkURL: storedArtwork.url
        )
        let scenario = Scenario(
            catalogLoads: [.success(originalSnapshot)],
            storedAudioLists: [.success([storedAudio])],
            metadata: [storedAudio.url: .success(metadata)],
            storedArtwork: [storedAudio.trackID: .success(storedArtwork)],
            resolvedURLs: [missingArtwork: .failure(.invalidManagedFile)]
        )
        let store = makeStore(scenario: scenario)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(originalSnapshot),
                storedAudio: .success([storedAudio])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: library,
                            catalog: replacement,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = library
            $0.loadStatus = .loaded
        }

        expectLoadCalls(
            scenario.calls.value,
            followedBy: [
                .resolveFileURL(missingArtwork),
                .readMetadata(storedAudio.url),
                .storeArtwork(artworkData, storedAudio.trackID),
                .replaceCatalog(replacement),
            ]
        )
    }

    @Test
    func unavailableArtworkFallsBackToNilWithoutBlockingPlayback() async {
        let storedAudio = makeStoredAudio()
        let missingArtwork = LibraryMediaStoreClient.FileReference(
            rawValue: "Artwork/missing"
        )
        let originalEntry = makeEntry(
            audioReference: storedAudio.reference,
            artworkReference: missingArtwork
        )
        let recoveredEntry = makeEntry(
            audioReference: storedAudio.reference,
            artworkReference: nil
        )
        let originalSnapshot = LibraryCatalogClient.Snapshot(
            entries: [originalEntry]
        )
        let replacement = LibraryCatalogClient.Snapshot(
            entries: [recoveredEntry]
        )
        let library = makeLibrary(
            entry: recoveredEntry,
            storedAudio: storedAudio,
            artworkURL: nil
        )
        let scenario = Scenario(
            catalogLoads: [.success(originalSnapshot)],
            storedAudioLists: [.success([storedAudio])],
            metadata: [storedAudio.url: .success(makeMetadata())],
            resolvedURLs: [missingArtwork: .failure(.invalidManagedFile)]
        )
        let store = makeStore(scenario: scenario)

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(originalSnapshot),
                storedAudio: .success([storedAudio])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: library,
                            catalog: replacement,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = library
            $0.loadStatus = .loaded
        }

        expectLoadCalls(
            scenario.calls.value,
            followedBy: [
                .resolveFileURL(missingArtwork),
                .readMetadata(storedAudio.url),
                .replaceCatalog(replacement),
            ]
        )
    }

    @Test
    func failedRefreshPreservesConfirmedLibraryAndRetryLoadsAgain() async {
        let confirmedEntry = makeEntry()
        let confirmedAudio = makeStoredAudio()
        let confirmedLibrary = makeLibrary(
            entry: confirmedEntry,
            storedAudio: confirmedAudio
        )
        let emptySnapshot = LibraryCatalogClient.Snapshot(entries: [])
        let emptyLibrary = Library(items: [])
        let scenario = Scenario(
            catalogLoads: [
                .success(emptySnapshot),
                .success(emptySnapshot),
            ],
            storedAudioLists: [
                .failure(.fileReadFailed),
                .success([]),
            ]
        )
        let store = makeStore(
            scenario: scenario,
            initialLibrary: confirmedLibrary
        )

        await store.send(.task) {
            $0.loadStatus = .loading
        }
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(emptySnapshot),
                storedAudio: .failure(.fileReadFailed)
            )
        ) {
            $0.loadStatus = .failed(.fileReadFailed)
        }
        #expect(store.state.library == confirmedLibrary)

        await store.send(.retryButtonTapped)
        await store.receive(.task) {
            $0.loadStatus = .loading
        }
        #expect(store.state.library == confirmedLibrary)
        await store.receive(
            .libraryLoadCompleted(
                catalog: .success(emptySnapshot),
                storedAudio: .success([])
            )
        )
        await store.receive(
            .recovery(
                .delegate(
                    .completed(
                        .init(
                            library: emptyLibrary,
                            catalog: emptySnapshot,
                            catalogWriteFailure: nil
                        )
                    )
                )
            )
        ) {
            $0.library = emptyLibrary
            $0.loadStatus = .loaded
        }

        let calls = scenario.calls.value
        #expect(calls.count == 4)
        expectLoadCalls(Array(calls.prefix(2)))
        expectLoadCalls(Array(calls.suffix(2)))
    }

    private func expectLoadCalls(
        _ calls: [Call],
        followedBy subsequentCalls: [Call] = []
    ) {
        #expect(calls.count == subsequentCalls.count + 2)
        guard calls.count >= 2 else { return }

        let loadCalls = Array(calls.prefix(2))
        #expect(loadCalls.contains(.loadCatalog))
        #expect(loadCalls.contains(.listStoredAudio))
        #expect(Array(calls.dropFirst(2)) == subsequentCalls)
    }

    private func makeStore(
        scenario: Scenario,
        initialLibrary: Library = Library(items: []),
        initialCatalog: LibraryCatalogClient.Snapshot = .init(entries: []),
        initialImportBatch: LibraryImportReducer.State? = nil
    ) -> TestStoreOf<LibraryReducer> {
        let store = TestStore(
            initialState: LibraryReducer.State(
                library: initialLibrary,
                catalog: initialCatalog,
                loadStatus: .idle,
                path: [],
                isFileImporterPresented: false,
                recovery: nil,
                importBatch: initialImportBatch,
                fileSelectionFailure: nil
            )
        ) {
            LibraryReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.libraryCatalog = scenario.catalogClient
            $0.libraryMediaStore = scenario.mediaStoreClient
            $0.audioMetadata = scenario.metadataClient
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    private func makeStoredAudio() -> LibraryMediaStoreClient.StoredAudio {
        LibraryMediaStoreClient.StoredAudio(
            trackID: makeTrackID(),
            reference: .init(
                rawValue: "Audio/01234567-89AB-CDEF-0123-456789ABCDEF.m4a"
            ),
            url: URL(
                fileURLWithPath:
                    "/managed/Audio/01234567-89AB-CDEF-0123-456789ABCDEF.m4a"
            ),
            creationDate: Date(timeIntervalSinceReferenceDate: 200)
        )
    }

    private func makeEntry(
        audioReference: LibraryMediaStoreClient.FileReference = .init(
            rawValue: "Audio/01234567-89AB-CDEF-0123-456789ABCDEF.m4a"
        ),
        contentIdentity: Library.ContentIdentity = Library.ContentIdentity(
            rawValue: String(repeating: "a", count: 64)
        ),
        title: String = "Catalog Song",
        artistName: String? = "Catalog Artist",
        albumTitle: String? = "Catalog Album",
        albumArtistName: String? = "Catalog Album Artist",
        duration: TimeInterval? = 30,
        trackNumber: Int? = 1,
        discNumber: Int? = 1,
        artworkReference: LibraryMediaStoreClient.FileReference? = nil,
        addedAt: Date = Date(timeIntervalSinceReferenceDate: 100)
    ) -> LibraryCatalogClient.Entry {
        LibraryCatalogClient.Entry(
            id: makeTrackID(),
            audioReference: audioReference,
            contentIdentity: contentIdentity,
            title: title,
            artistName: artistName,
            albumTitle: albumTitle,
            albumArtistName: albumArtistName,
            duration: duration,
            trackNumber: trackNumber,
            discNumber: discNumber,
            artworkReference: artworkReference,
            addedAt: addedAt
        )
    }

    private func makeLibrary(
        entry: LibraryCatalogClient.Entry,
        storedAudio: LibraryMediaStoreClient.StoredAudio,
        artworkURL: URL? = nil
    ) -> Library {
        Library(
            items: [
                Library.Item(
                    track: Track(
                        id: entry.id,
                        title: entry.title,
                        artistName: entry.artistName,
                        albumTitle: entry.albumTitle,
                        artworkURL: artworkURL,
                        duration: entry.duration,
                        playbackURL: storedAudio.url
                    ),
                    contentIdentity: entry.contentIdentity,
                    addedAt: entry.addedAt
                )
            ]
        )
    }

    private func makeTrackID() -> TrackID {
        TrackID(
            providerID: .library,
            nativeID: "01234567-89AB-CDEF-0123-456789ABCDEF"
        )
    }

    private func makeContentIdentity() -> Library.ContentIdentity {
        Library.ContentIdentity(
            rawValue: String(repeating: "b", count: 64)
        )
    }

    private func makeMetadata(
        title: String? = "Recovered Song",
        artworkData: Data? = nil
    ) -> AudioMetadataClient.Metadata {
        AudioMetadataClient.Metadata(
            title: title,
            artistName: "Recovered Artist",
            albumTitle: "Recovered Album",
            albumArtistName: "Recovered Album Artist",
            duration: 42,
            trackNumber: 2,
            discNumber: 1,
            artworkData: artworkData
        )
    }
}

private extension LibraryReducerTests {
    enum Call: Equatable {
        case loadCatalog
        case replaceCatalog(LibraryCatalogClient.Snapshot)
        case listStoredAudio
        case identifyAudio(URL)
        case readMetadata(URL)
        case storeArtwork(Data, TrackID)
        case resolveFileURL(LibraryMediaStoreClient.FileReference)
        case stageAudio
        case storeAudio
        case discardStagedAudio
    }

    struct Scenario: Sendable {
        typealias CatalogLoadResult = Result<
            LibraryCatalogClient.Snapshot,
            LibraryFailure
        >
        typealias StoredAudioListResult = Result<
            [LibraryMediaStoreClient.StoredAudio],
            LibraryFailure
        >
        typealias IdentityResult = Result<
            Library.ContentIdentity,
            LibraryFailure
        >
        typealias MetadataResult = Result<
            AudioMetadataClient.Metadata,
            LibraryFailure
        >
        typealias StoredArtworkResult = Result<
            LibraryMediaStoreClient.StoredArtwork,
            LibraryFailure
        >
        typealias ResolvedURLResult = Result<URL, LibraryFailure>
        typealias ResolvedURLs = [LibraryMediaStoreClient.FileReference: ResolvedURLResult]

        let calls = LockIsolated<[Call]>([])

        private let catalogLoads: LockIsolated<[CatalogLoadResult]>
        private let storedAudioLists: LockIsolated<[StoredAudioListResult]>
        private let catalogReplaceFailure: LibraryFailure?
        private let identities: [URL: IdentityResult]
        private let metadata: [URL: MetadataResult]
        private let storedArtwork: [TrackID: StoredArtworkResult]
        private let resolvedURLs: ResolvedURLs

        init(
            catalogLoads: [CatalogLoadResult] = [.success(.init(entries: []))],
            storedAudioLists: [StoredAudioListResult] = [.success([])],
            catalogReplaceFailure: LibraryFailure? = nil,
            identities: [URL: IdentityResult] = [:],
            metadata: [URL: MetadataResult] = [:],
            storedArtwork: [TrackID: StoredArtworkResult] = [:],
            resolvedURLs: ResolvedURLs = [:]
        ) {
            self.catalogLoads = LockIsolated(catalogLoads)
            self.storedAudioLists = LockIsolated(storedAudioLists)
            self.catalogReplaceFailure = catalogReplaceFailure
            self.identities = identities
            self.metadata = metadata
            self.storedArtwork = storedArtwork
            self.resolvedURLs = resolvedURLs
        }

        var catalogClient: LibraryCatalogClient {
            let calls = calls
            let catalogLoads = catalogLoads
            let catalogReplaceFailure = catalogReplaceFailure
            return LibraryCatalogClient(
                load: {
                    calls.withValue { $0.append(.loadCatalog) }
                    return catalogLoads.withValue { results in
                        guard !results.isEmpty else {
                            return .failure(.catalogReadFailed)
                        }
                        return results.removeFirst()
                    }
                },
                replace: { snapshot in
                    calls.withValue { $0.append(.replaceCatalog(snapshot)) }
                    if let catalogReplaceFailure {
                        return .failure(catalogReplaceFailure)
                    }
                    return .success(snapshot)
                }
            )
        }

        var mediaStoreClient: LibraryMediaStoreClient {
            let calls = calls
            let storedAudioLists = storedAudioLists
            let identities = identities
            let storedArtwork = storedArtwork
            let resolvedURLs = resolvedURLs
            return LibraryMediaStoreClient(
                stageAudio: { _ in
                    calls.withValue { $0.append(.stageAudio) }
                    return .failure(.fileReadFailed)
                },
                storeAudio: { _, _ in
                    calls.withValue { $0.append(.storeAudio) }
                    return .failure(.fileWriteFailed)
                },
                discardStagedAudio: { _ in
                    calls.withValue { $0.append(.discardStagedAudio) }
                },
                listStoredAudio: {
                    calls.withValue { $0.append(.listStoredAudio) }
                    return storedAudioLists.withValue { results in
                        guard !results.isEmpty else {
                            return .failure(.fileReadFailed)
                        }
                        return results.removeFirst()
                    }
                },
                identifyAudio: { url in
                    calls.withValue { $0.append(.identifyAudio(url)) }
                    return identities[url] ?? .failure(.fileReadFailed)
                },
                storeArtwork: { data, trackID in
                    calls.withValue {
                        $0.append(.storeArtwork(data, trackID))
                    }
                    return storedArtwork[trackID] ?? .failure(.fileWriteFailed)
                },
                resolveFileURL: { reference in
                    calls.withValue { $0.append(.resolveFileURL(reference)) }
                    return resolvedURLs[reference]
                        ?? .failure(.invalidManagedFile)
                }
            )
        }

        var metadataClient: AudioMetadataClient {
            let calls = calls
            let metadata = metadata
            return AudioMetadataClient(
                read: { url in
                    calls.withValue { $0.append(.readMetadata(url)) }
                    return metadata[url] ?? .failure(.metadataReadFailed)
                }
            )
        }
    }
}
