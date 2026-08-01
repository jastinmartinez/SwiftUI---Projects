import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct LibraryImportReducerTests {
    @Test
    func supportedFileCompletesWithUpdatedLibraryAndCatalog() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let stagedAudio = makeStagedAudio()
        let metadata = makeMetadata()
        let trackID = TrackID(
            providerID: .library,
            nativeID: UUID(0).uuidString
        )
        let storedAudio = makeStoredAudio(trackID: trackID)
        let entry = makeEntry(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata
        )
        let item = makeItem(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata
        )
        let catalog = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = Library(items: [item])
        let summary = LibraryImportReducer.Summary(
            importedCount: 1,
            duplicateCount: 0,
            issues: []
        )
        let completion = LibraryImportReducer.Completion(
            library: library,
            catalog: catalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .success(metadata),
            storedAudio: .success(storedAudio),
            catalogReplacement: .success(catalog)
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == library)
        #expect(store.state.workingCatalog == catalog)
        #expect(store.state.lifecycle == .completed(summary))
        #expect(store.state.phase == .completed)
        #expect(
            scenario.calls.value == [
                .stageAudio(sourceURL),
                .readMetadata(stagedAudio.temporaryURL),
                .storeAudio(stagedAudio, trackID),
                .replaceCatalog(catalog),
            ]
        )
    }

    @Test
    func stagingFailureCompletesBatchWithIssue() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let issue = LibraryImportReducer.Issue(
            id: UUID(0),
            sourceName: "Song.m4a",
            failure: .unsupportedFile
        )
        let summary = LibraryImportReducer.Summary(
            importedCount: 0,
            duplicateCount: 0,
            issues: [issue]
        )
        let emptyLibrary = Library(items: [])
        let emptyCatalog = LibraryCatalogClient.Snapshot(entries: [])
        let completion = LibraryImportReducer.Completion(
            library: emptyLibrary,
            catalog: emptyCatalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .failure(.unsupportedFile),
            metadata: .failure(.metadataReadFailed),
            storedAudio: .failure(.fileWriteFailed),
            catalogReplacement: .failure(.catalogWriteFailed)
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == emptyLibrary)
        #expect(store.state.workingCatalog == emptyCatalog)
        #expect(store.state.lifecycle == .completed(summary))
        #expect(store.state.phase == .completed)
        #expect(scenario.calls.value == [.stageAudio(sourceURL)])
    }

    @Test
    func duplicateContentDiscardsStagedAudioWithoutIssue() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let stagedAudio = makeStagedAudio()
        let metadata = makeMetadata()
        let existingTrackID = TrackID(
            providerID: .library,
            nativeID: "existing"
        )
        let existingStoredAudio = makeStoredAudio(trackID: existingTrackID)
        let existingEntry = makeEntry(
            trackID: existingTrackID,
            stagedAudio: stagedAudio,
            storedAudio: existingStoredAudio,
            metadata: metadata
        )
        let existingItem = makeItem(
            trackID: existingTrackID,
            stagedAudio: stagedAudio,
            storedAudio: existingStoredAudio,
            metadata: metadata
        )
        let library = Library(items: [existingItem])
        let catalog = LibraryCatalogClient.Snapshot(entries: [existingEntry])
        let summary = LibraryImportReducer.Summary(
            importedCount: 0,
            duplicateCount: 1,
            issues: []
        )
        let completion = LibraryImportReducer.Completion(
            library: library,
            catalog: catalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .failure(.metadataReadFailed),
            storedAudio: .failure(.fileWriteFailed),
            catalogReplacement: .failure(.catalogWriteFailed)
        )
        let store = makeStore(
            sources: [sourceURL],
            library: library,
            catalog: catalog,
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == library)
        #expect(store.state.workingCatalog == catalog)
        #expect(store.state.lifecycle == .completed(summary))
        #expect(store.state.phase == .completed)
        #expect(
            scenario.calls.value == [
                .stageAudio(sourceURL),
                .discardStagedAudio(stagedAudio),
            ]
        )
    }

    @Test
    func metadataFailureDiscardsStagedAudioAndRecordsIssue() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let stagedAudio = makeStagedAudio()
        let issue = LibraryImportReducer.Issue(
            id: UUID(1),
            sourceName: stagedAudio.sourceName,
            failure: .metadataReadFailed
        )
        let summary = LibraryImportReducer.Summary(
            importedCount: 0,
            duplicateCount: 0,
            issues: [issue]
        )
        let emptyLibrary = Library(items: [])
        let emptyCatalog = LibraryCatalogClient.Snapshot(entries: [])
        let completion = LibraryImportReducer.Completion(
            library: emptyLibrary,
            catalog: emptyCatalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .failure(.metadataReadFailed),
            storedAudio: .failure(.fileWriteFailed),
            catalogReplacement: .failure(.catalogWriteFailed)
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == emptyLibrary)
        #expect(store.state.workingCatalog == emptyCatalog)
        #expect(store.state.lifecycle == .completed(summary))
        #expect(store.state.phase == .completed)
        #expect(
            scenario.calls.value == [
                .stageAudio(sourceURL),
                .readMetadata(stagedAudio.temporaryURL),
                .discardStagedAudio(stagedAudio),
            ]
        )
    }

    @Test
    func audioStorageFailureDiscardsStagedAudioAndRecordsIssue() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let stagedAudio = makeStagedAudio()
        let metadata = makeMetadata()
        let trackID = TrackID(
            providerID: .library,
            nativeID: UUID(0).uuidString
        )
        let issue = LibraryImportReducer.Issue(
            id: UUID(1),
            sourceName: stagedAudio.sourceName,
            failure: .fileWriteFailed
        )
        let summary = LibraryImportReducer.Summary(
            importedCount: 0,
            duplicateCount: 0,
            issues: [issue]
        )
        let emptyLibrary = Library(items: [])
        let emptyCatalog = LibraryCatalogClient.Snapshot(entries: [])
        let completion = LibraryImportReducer.Completion(
            library: emptyLibrary,
            catalog: emptyCatalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .success(metadata),
            storedAudio: .failure(.fileWriteFailed),
            catalogReplacement: .failure(.catalogWriteFailed)
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == emptyLibrary)
        #expect(store.state.workingCatalog == emptyCatalog)
        #expect(store.state.lifecycle == .completed(summary))
        #expect(store.state.phase == .completed)
        #expect(
            scenario.calls.value == [
                .stageAudio(sourceURL),
                .readMetadata(stagedAudio.temporaryURL),
                .storeAudio(stagedAudio, trackID),
                .discardStagedAudio(stagedAudio),
            ]
        )
    }

    @Test
    func catalogFailureKeepsManagedItemAndRecordsIssue() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let stagedAudio = makeStagedAudio()
        let metadata = makeMetadata()
        let trackID = TrackID(
            providerID: .library,
            nativeID: UUID(0).uuidString
        )
        let storedAudio = makeStoredAudio(trackID: trackID)
        let entry = makeEntry(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata
        )
        let item = makeItem(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata
        )
        let catalog = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = Library(items: [item])
        let issue = LibraryImportReducer.Issue(
            id: UUID(1),
            sourceName: stagedAudio.sourceName,
            failure: .catalogWriteFailed
        )
        let summary = LibraryImportReducer.Summary(
            importedCount: 1,
            duplicateCount: 0,
            issues: [issue]
        )
        let completion = LibraryImportReducer.Completion(
            library: library,
            catalog: catalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .success(metadata),
            storedAudio: .success(storedAudio),
            catalogReplacement: .failure(.catalogWriteFailed)
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == library)
        #expect(store.state.workingCatalog == catalog)
        #expect(store.state.lifecycle == .completed(summary))
        #expect(store.state.phase == .completed)
        #expect(
            scenario.calls.value == [
                .stageAudio(sourceURL),
                .readMetadata(stagedAudio.temporaryURL),
                .storeAudio(stagedAudio, trackID),
                .replaceCatalog(catalog),
            ]
        )
    }

    @Test
    func embeddedArtworkIsStoredBeforeCatalogReplacement() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let artworkData = Data("artwork".utf8)
        let stagedAudio = makeStagedAudio()
        let metadata = makeMetadata(artworkData: artworkData)
        let trackID = TrackID(
            providerID: .library,
            nativeID: UUID(0).uuidString
        )
        let storedAudio = makeStoredAudio(trackID: trackID)
        let storedArtwork = LibraryMediaStoreClient.StoredArtwork(
            reference: .init(rawValue: "Artwork/\(trackID.nativeID).jpg"),
            url: URL(
                fileURLWithPath: "/managed/Artwork/\(trackID.nativeID).jpg"
            )
        )
        let entry = makeEntry(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata,
            storedArtwork: storedArtwork
        )
        let item = makeItem(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata,
            storedArtwork: storedArtwork
        )
        let catalog = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = Library(items: [item])
        let summary = LibraryImportReducer.Summary(
            importedCount: 1,
            duplicateCount: 0,
            issues: []
        )
        let completion = LibraryImportReducer.Completion(
            library: library,
            catalog: catalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .success(metadata),
            storedAudio: .success(storedAudio),
            catalogReplacement: .success(catalog),
            storedArtwork: .success(storedArtwork)
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == library)
        #expect(store.state.workingCatalog == catalog)
        #expect(store.state.lifecycle == .completed(summary))
        #expect(store.state.phase == .completed)
        #expect(
            scenario.calls.value == [
                .stageAudio(sourceURL),
                .readMetadata(stagedAudio.temporaryURL),
                .storeAudio(stagedAudio, trackID),
                .storeArtwork(artworkData, trackID),
                .replaceCatalog(catalog),
            ]
        )
    }

    @Test
    func artworkFailureKeepsPlayableItemWithoutArtwork() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let artworkData = Data("artwork".utf8)
        let stagedAudio = makeStagedAudio()
        let metadata = makeMetadata(artworkData: artworkData)
        let trackID = TrackID(
            providerID: .library,
            nativeID: UUID(0).uuidString
        )
        let storedAudio = makeStoredAudio(trackID: trackID)
        let entry = makeEntry(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata
        )
        let item = makeItem(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata
        )
        let catalog = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = Library(items: [item])
        let issue = LibraryImportReducer.Issue(
            id: UUID(1),
            sourceName: stagedAudio.sourceName,
            failure: .fileWriteFailed
        )
        let summary = LibraryImportReducer.Summary(
            importedCount: 1,
            duplicateCount: 0,
            issues: [issue]
        )
        let completion = LibraryImportReducer.Completion(
            library: library,
            catalog: catalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .success(metadata),
            storedAudio: .success(storedAudio),
            catalogReplacement: .success(catalog),
            storedArtwork: .failure(.fileWriteFailed)
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == library)
        #expect(store.state.workingCatalog == catalog)
        #expect(store.state.lifecycle == .completed(summary))
        #expect(store.state.phase == .completed)
        #expect(
            scenario.calls.value == [
                .stageAudio(sourceURL),
                .readMetadata(stagedAudio.temporaryURL),
                .storeAudio(stagedAudio, trackID),
                .storeArtwork(artworkData, trackID),
                .replaceCatalog(catalog),
            ]
        )
    }

    @Test(arguments: [String?.none, "   "])
    func missingMetadataTitleUsesSourceFilenameStem(
        _ metadataTitle: String?
    ) async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let stagedAudio = makeStagedAudio()
        let metadata = makeMetadata(title: metadataTitle)
        let trackID = TrackID(
            providerID: .library,
            nativeID: UUID(0).uuidString
        )
        let storedAudio = makeStoredAudio(trackID: trackID)
        let entry = makeEntry(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata,
            expectedTitle: "Song"
        )
        let item = makeItem(
            trackID: trackID,
            stagedAudio: stagedAudio,
            storedAudio: storedAudio,
            metadata: metadata,
            expectedTitle: "Song"
        )
        let catalog = LibraryCatalogClient.Snapshot(entries: [entry])
        let library = Library(items: [item])
        let summary = LibraryImportReducer.Summary(
            importedCount: 1,
            duplicateCount: 0,
            issues: []
        )
        let completion = LibraryImportReducer.Completion(
            library: library,
            catalog: catalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .success(metadata),
            storedAudio: .success(storedAudio),
            catalogReplacement: .success(catalog)
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario
        )

        await store.send(.start)
        await store.receive(.delegate(.completed(completion)))

        #expect(store.state.workingLibrary == library)
        #expect(store.state.workingCatalog == catalog)
        #expect(store.state.lifecycle == .completed(summary))
    }

    @Test
    func cancellationDuringMetadataDiscardsStagedAudio() async {
        let sourceURL = URL(fileURLWithPath: "/external/Song.m4a")
        let stagedAudio = makeStagedAudio()
        let suspendedMetadata = SuspendedOperationProbe<
            Result<AudioMetadataClient.Metadata, LibraryFailure>
        >()
        let summary = LibraryImportReducer.Summary(
            importedCount: 0,
            duplicateCount: 0,
            issues: []
        )
        let emptyLibrary = Library(items: [])
        let emptyCatalog = LibraryCatalogClient.Snapshot(entries: [])
        let completion = LibraryImportReducer.Completion(
            library: emptyLibrary,
            catalog: emptyCatalog,
            summary: summary
        )
        let scenario = Scenario(
            stagedAudio: .success(stagedAudio),
            metadata: .failure(.metadataReadFailed),
            storedAudio: .failure(.fileWriteFailed),
            catalogReplacement: .failure(.catalogWriteFailed)
        )
        let calls = scenario.calls
        let metadataClient = AudioMetadataClient(
            read: { url in
                calls.withValue { $0.append(.readMetadata(url)) }
                do {
                    return try await suspendedMetadata.run()
                } catch {
                    return .failure(.metadataReadFailed)
                }
            }
        )
        let store = makeStore(
            sources: [sourceURL],
            scenario: scenario,
            metadataClient: metadataClient
        )

        await store.send(.start)
        await suspendedMetadata.waitUntilStarted()
        await store.send(.cancelButtonTapped)
        await suspendedMetadata.waitUntilCancelled()
        await store.receive(.delegate(.cancelled(completion)))

        #expect(store.state.workingLibrary == emptyLibrary)
        #expect(store.state.workingCatalog == emptyCatalog)
        #expect(store.state.lifecycle == .cancelled(summary))
        #expect(store.state.phase == .completed)
        #expect(
            scenario.calls.value == [
                .stageAudio(sourceURL),
                .readMetadata(stagedAudio.temporaryURL),
                .discardStagedAudio(stagedAudio),
            ]
        )
    }
}

private extension LibraryImportReducerTests {
    func makeStore(
        sources: [URL],
        library: Library = Library(items: []),
        catalog: LibraryCatalogClient.Snapshot = .init(entries: []),
        scenario: Scenario,
        metadataClient: AudioMetadataClient? = nil
    ) -> TestStoreOf<LibraryImportReducer> {
        let store = TestStore(
            initialState: LibraryImportReducer.State(
                sources: sources,
                library: library,
                catalog: catalog
            )
        ) {
            LibraryImportReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.libraryCatalog = scenario.catalogClient
            $0.libraryMediaStore = scenario.mediaStoreClient
            $0.audioMetadata = metadataClient ?? scenario.metadataClient
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    func makeStagedAudio() -> LibraryMediaStoreClient.StagedAudio {
        LibraryMediaStoreClient.StagedAudio(
            sourceName: "Song.m4a",
            temporaryURL: URL(fileURLWithPath: "/staging/Song.m4a"),
            fileExtension: .init(rawValue: "m4a"),
            contentIdentity: .init(rawValue: "song-content")
        )
    }

    func makeStoredAudio(
        trackID: TrackID
    ) -> LibraryMediaStoreClient.StoredAudio {
        LibraryMediaStoreClient.StoredAudio(
            trackID: trackID,
            reference: .init(rawValue: "Audio/\(trackID.nativeID).m4a"),
            url: URL(fileURLWithPath: "/managed/Audio/\(trackID.nativeID).m4a"),
            creationDate: Date(timeIntervalSinceReferenceDate: 100)
        )
    }

    func makeMetadata(
        title: String? = "Song Title",
        artworkData: Data? = nil
    ) -> AudioMetadataClient.Metadata {
        AudioMetadataClient.Metadata(
            title: title,
            artistName: "Artist",
            albumTitle: "Album",
            albumArtistName: "Album Artist",
            duration: 42,
            trackNumber: 2,
            discNumber: 1,
            artworkData: artworkData
        )
    }

    func makeEntry(
        trackID: TrackID,
        stagedAudio: LibraryMediaStoreClient.StagedAudio,
        storedAudio: LibraryMediaStoreClient.StoredAudio,
        metadata: AudioMetadataClient.Metadata,
        expectedTitle: String = "Song Title",
        storedArtwork: LibraryMediaStoreClient.StoredArtwork? = nil
    ) -> LibraryCatalogClient.Entry {
        LibraryCatalogClient.Entry(
            id: trackID,
            audioReference: storedAudio.reference,
            contentIdentity: stagedAudio.contentIdentity,
            title: expectedTitle,
            artistName: metadata.artistName,
            albumTitle: metadata.albumTitle,
            albumArtistName: metadata.albumArtistName,
            duration: metadata.duration,
            trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber,
            artworkReference: storedArtwork?.reference,
            addedAt: storedAudio.creationDate
        )
    }

    func makeItem(
        trackID: TrackID,
        stagedAudio: LibraryMediaStoreClient.StagedAudio,
        storedAudio: LibraryMediaStoreClient.StoredAudio,
        metadata: AudioMetadataClient.Metadata,
        expectedTitle: String = "Song Title",
        storedArtwork: LibraryMediaStoreClient.StoredArtwork? = nil
    ) -> Library.Item {
        Library.Item(
            track: Track(
                id: trackID,
                title: expectedTitle,
                artistName: metadata.artistName,
                albumTitle: metadata.albumTitle,
                artworkURL: storedArtwork?.url,
                duration: metadata.duration,
                playbackURL: storedAudio.url
            ),
            contentIdentity: stagedAudio.contentIdentity,
            addedAt: storedAudio.creationDate
        )
    }
}

private extension LibraryImportReducerTests {
    enum Call: Equatable {
        case stageAudio(URL)
        case readMetadata(URL)
        case storeAudio(
            LibraryMediaStoreClient.StagedAudio,
            TrackID
        )
        case replaceCatalog(LibraryCatalogClient.Snapshot)
        case discardStagedAudio(LibraryMediaStoreClient.StagedAudio)
        case storeArtwork(Data, TrackID)
    }

    struct Scenario: Sendable {
        let calls = LockIsolated<[Call]>([])
        let stagedAudio:
            Result<
                LibraryMediaStoreClient.StagedAudio,
                LibraryFailure
            >
        let metadata:
            Result<
                AudioMetadataClient.Metadata,
                LibraryFailure
            >
        let storedAudio:
            Result<
                LibraryMediaStoreClient.StoredAudio,
                LibraryFailure
            >
        let catalogReplacement:
            Result<
                LibraryCatalogClient.Snapshot,
                LibraryFailure
            >
        let storedArtwork:
            Result<
                LibraryMediaStoreClient.StoredArtwork,
                LibraryFailure
            >

        init(
            stagedAudio: Result<
                LibraryMediaStoreClient.StagedAudio,
                LibraryFailure
            >,
            metadata: Result<
                AudioMetadataClient.Metadata,
                LibraryFailure
            >,
            storedAudio: Result<
                LibraryMediaStoreClient.StoredAudio,
                LibraryFailure
            >,
            catalogReplacement: Result<
                LibraryCatalogClient.Snapshot,
                LibraryFailure
            >,
            storedArtwork: Result<
                LibraryMediaStoreClient.StoredArtwork,
                LibraryFailure
            > = .failure(.fileWriteFailed)
        ) {
            self.stagedAudio = stagedAudio
            self.metadata = metadata
            self.storedAudio = storedAudio
            self.catalogReplacement = catalogReplacement
            self.storedArtwork = storedArtwork
        }

        var mediaStoreClient: LibraryMediaStoreClient {
            let calls = calls
            let stagedAudio = stagedAudio
            let storedAudio = storedAudio
            let storedArtwork = storedArtwork
            return LibraryMediaStoreClient(
                stageAudio: { url in
                    calls.withValue { $0.append(.stageAudio(url)) }
                    return stagedAudio
                },
                storeAudio: { stagedAudio, trackID in
                    calls.withValue {
                        $0.append(.storeAudio(stagedAudio, trackID))
                    }
                    return storedAudio
                },
                discardStagedAudio: { stagedAudio in
                    calls.withValue {
                        $0.append(.discardStagedAudio(stagedAudio))
                    }
                },
                listStoredAudio: {
                    Issue.record("Unexpected managed-audio listing")
                    return .failure(.fileReadFailed)
                },
                identifyAudio: { _ in
                    Issue.record("Unexpected audio identification")
                    return .failure(.fileReadFailed)
                },
                storeArtwork: { data, trackID in
                    calls.withValue {
                        $0.append(.storeArtwork(data, trackID))
                    }
                    return storedArtwork
                },
                resolveFileURL: { _ in
                    Issue.record("Unexpected managed-file resolution")
                    return .failure(.invalidManagedFile)
                }
            )
        }

        var metadataClient: AudioMetadataClient {
            let calls = calls
            let metadata = metadata
            return AudioMetadataClient(
                read: { url in
                    calls.withValue { $0.append(.readMetadata(url)) }
                    return metadata
                }
            )
        }

        var catalogClient: LibraryCatalogClient {
            let calls = calls
            let catalogReplacement = catalogReplacement
            return LibraryCatalogClient(
                load: {
                    Issue.record("Unexpected catalog load")
                    return .failure(.catalogReadFailed)
                },
                replace: { catalog in
                    calls.withValue { $0.append(.replaceCatalog(catalog)) }
                    return catalogReplacement
                }
            )
        }
    }
}
