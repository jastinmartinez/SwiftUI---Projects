import ComposableArchitecture
import Foundation

/// Imports one external audio source through the complete managed-media workflow.
///
/// The reducer stages the source, enforces duplicate-content policy against the
/// supplied working Library, extracts metadata, promotes audio, stores optional
/// artwork, and replaces the supplied working catalog. It reports imported,
/// duplicate, or failed facts to the batch reducer. It does not own batch
/// progress, the confirmed Library, picker presentation, navigation, or playback.
@Reducer
struct LibraryItemImportReducer {
    @ObservableState
    struct State: Equatable {
        let source: URL
        let library: Library
        let catalog: LibraryCatalogClient.Snapshot
        var issues: [LibraryImportReducer.Issue]
        var phase: Phase

        init(
            source: URL,
            library: Library,
            catalog: LibraryCatalogClient.Snapshot
        ) {
            self.source = source
            self.library = library
            self.catalog = catalog
            issues = []
            phase = .ready
        }
    }

    enum Action: Equatable {
        case start
        case cancelButtonTapped
        case cancellationCleanupCompleted
        case audioStagingCompleted(
            Result<
                LibraryMediaStoreClient.StagedAudio,
                LibraryFailure
            >
        )
        case metadataReadCompleted(
            Result<
                AudioMetadataClient.Metadata,
                LibraryFailure
            >
        )
        case audioStorageCompleted(
            Result<
                LibraryMediaStoreClient.StoredAudio,
                LibraryFailure
            >
        )
        case artworkStorageCompleted(
            Result<
                LibraryMediaStoreClient.StoredArtwork,
                LibraryFailure
            >
        )
        case catalogPreparationRequested
        case catalogReplacementCompleted(
            Result<
                LibraryCatalogClient.Snapshot,
                LibraryFailure
            >
        )
        case duplicateStagedAudioDiscarded
        case failedStagedAudioDiscarded
        case fileFailed(LibraryFailure)
        case delegate(Delegate)
    }

    @Dependency(\.audioMetadata) private var audioMetadata
    @Dependency(\.libraryCatalog) private var libraryCatalog
    @Dependency(\.libraryMediaStore) private var libraryMediaStore
    @Dependency(\.uuid) private var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                guard state.phase == .ready else { return .none }
                state.phase = .staging
                let source = state.source
                return .run { send in
                    let result = await libraryMediaStore.stageAudio(source)
                    await send(.audioStagingCompleted(result))
                }
                .cancellable(id: CancelID.operation, cancelInFlight: true)

            case .cancelButtonTapped:
                switch state.phase {
                case .ready:
                    state.phase = .completed
                    return .send(.delegate(.cancelled))

                case .staging:
                    state.phase = .completed
                    return .merge(
                        .cancel(id: CancelID.operation),
                        .send(.delegate(.cancelled))
                    )

                case let .readingMetadata(stagedAudio, _):
                    state.phase = .cancelling(stagedAudio: stagedAudio)
                    return .merge(
                        .cancel(id: CancelID.operation),
                        .run { send in
                            await libraryMediaStore.discardStagedAudio(
                                stagedAudio
                            )
                            await send(.cancellationCleanupCompleted)
                        }
                    )

                case .discardingDuplicate,
                    .discardingFailedImport,
                    .storingAudio,
                    .storingArtwork,
                    .preparingCatalog,
                    .replacingCatalog:
                    return .none

                case .cancelling, .completed:
                    return .none
                }

            case .cancellationCleanupCompleted:
                guard case .cancelling = state.phase else { return .none }
                state.phase = .completed
                return .send(.delegate(.cancelled))

            case let .audioStagingCompleted(result):
                guard state.phase == .staging else { return .none }

                switch result {
                case let .success(stagedAudio):
                    guard
                        !state.library.contains(stagedAudio.contentIdentity)
                    else {
                        state.phase = .discardingDuplicate(
                            stagedAudio: stagedAudio
                        )
                        return .run { send in
                            await libraryMediaStore.discardStagedAudio(
                                stagedAudio
                            )
                            await send(.duplicateStagedAudioDiscarded)
                        }
                    }

                    let trackID = TrackID(
                        providerID: .library,
                        nativeID: uuid().uuidString
                    )
                    state.phase = .readingMetadata(
                        stagedAudio: stagedAudio,
                        trackID: trackID
                    )
                    return .run { send in
                        let result = await audioMetadata.read(
                            stagedAudio.temporaryURL
                        )
                        await send(.metadataReadCompleted(result))
                    }
                    .cancellable(
                        id: CancelID.operation,
                        cancelInFlight: true
                    )

                case let .failure(failure):
                    return .send(.fileFailed(failure))
                }

            case let .metadataReadCompleted(result):
                guard
                    case let .readingMetadata(stagedAudio, trackID) = state.phase
                else {
                    return .none
                }

                switch result {
                case let .success(metadata):
                    state.phase = .storingAudio(
                        stagedAudio: stagedAudio,
                        trackID: trackID,
                        metadata: metadata
                    )
                    return .run { send in
                        let result = await libraryMediaStore.storeAudio(
                            stagedAudio,
                            trackID
                        )
                        await send(.audioStorageCompleted(result))
                    }

                case let .failure(failure):
                    state.phase = .discardingFailedImport(
                        stagedAudio: stagedAudio,
                        failure: failure
                    )
                    return .run { send in
                        await libraryMediaStore.discardStagedAudio(stagedAudio)
                        await send(.failedStagedAudioDiscarded)
                    }
                }

            case let .audioStorageCompleted(result):
                guard
                    case let .storingAudio(
                        stagedAudio,
                        _,
                        metadata
                    ) = state.phase
                else {
                    return .none
                }

                switch result {
                case let .success(storedAudio):
                    if let artworkData = metadata.artworkData {
                        state.phase = .storingArtwork(
                            stagedAudio: stagedAudio,
                            storedAudio: storedAudio,
                            metadata: metadata
                        )
                        return .run { send in
                            let result = await libraryMediaStore.storeArtwork(
                                artworkData,
                                storedAudio.trackID
                            )
                            await send(.artworkStorageCompleted(result))
                        }
                    }

                    state.phase = .preparingCatalog(
                        stagedAudio: stagedAudio,
                        storedAudio: storedAudio,
                        metadata: metadata,
                        storedArtwork: nil
                    )
                    return .send(.catalogPreparationRequested)

                case let .failure(failure):
                    state.phase = .discardingFailedImport(
                        stagedAudio: stagedAudio,
                        failure: failure
                    )
                    return .run { send in
                        await libraryMediaStore.discardStagedAudio(stagedAudio)
                        await send(.failedStagedAudioDiscarded)
                    }
                }

            case let .artworkStorageCompleted(result):
                guard
                    case let .storingArtwork(
                        stagedAudio,
                        storedAudio,
                        metadata
                    ) = state.phase
                else {
                    return .none
                }

                switch result {
                case let .success(storedArtwork):
                    state.phase = .preparingCatalog(
                        stagedAudio: stagedAudio,
                        storedAudio: storedAudio,
                        metadata: metadata,
                        storedArtwork: storedArtwork
                    )

                case let .failure(failure):
                    state.issues.append(
                        LibraryImportReducer.Issue(
                            id: uuid(),
                            sourceName: state.source.lastPathComponent,
                            failure: failure
                        )
                    )
                    state.phase = .preparingCatalog(
                        stagedAudio: stagedAudio,
                        storedAudio: storedAudio,
                        metadata: metadata,
                        storedArtwork: nil
                    )
                }
                return .send(.catalogPreparationRequested)

            case .catalogPreparationRequested:
                guard
                    case let .preparingCatalog(
                        stagedAudio,
                        storedAudio,
                        metadata,
                        storedArtwork
                    ) = state.phase
                else {
                    return .none
                }

                let entry = LibraryCatalogClient.Entry(
                    stagedAudio: stagedAudio,
                    storedAudio: storedAudio,
                    metadata: metadata,
                    storedArtwork: storedArtwork
                )
                let item = Library.Item(
                    catalogEntry: entry,
                    storedAudio: storedAudio,
                    artworkURL: storedArtwork?.url
                )
                var entries = state.catalog.entries
                entries.updateOrAppend(entry)
                let catalog = LibraryCatalogClient.Snapshot(entries: entries)
                state.phase = .replacingCatalog(
                    item: item,
                    catalog: catalog
                )
                return .run { send in
                    let result = await libraryCatalog.replace(catalog)
                    await send(.catalogReplacementCompleted(result))
                }

            case let .catalogReplacementCompleted(result):
                guard
                    case let .replacingCatalog(item, catalog) = state.phase
                else {
                    return .none
                }

                state.phase = .completed
                switch result {
                case .success:
                    return .send(
                        .delegate(
                            .imported(
                                ImportedItem(
                                    item: item,
                                    catalog: catalog,
                                    issues: state.issues
                                )
                            )
                        )
                    )
                case let .failure(failure):
                    return .send(.fileFailed(failure))
                }

            case .duplicateStagedAudioDiscarded:
                guard case .discardingDuplicate = state.phase else {
                    return .none
                }
                state.phase = .completed
                return .send(.delegate(.duplicate))

            case .failedStagedAudioDiscarded:
                guard
                    case let .discardingFailedImport(_, failure) = state.phase
                else {
                    return .none
                }
                return .send(.fileFailed(failure))

            case let .fileFailed(failure):
                let issue = LibraryImportReducer.Issue(
                    id: uuid(),
                    sourceName: state.source.lastPathComponent,
                    failure: failure
                )
                state.phase = .completed
                return .send(.delegate(.failed(issue)))

            case .delegate:
                return .none
            }
        }
    }
}

private extension LibraryItemImportReducer {
    enum CancelID {
        case operation
    }
}

private extension LibraryCatalogClient.Entry {
    init(
        stagedAudio: LibraryMediaStoreClient.StagedAudio,
        storedAudio: LibraryMediaStoreClient.StoredAudio,
        metadata: AudioMetadataClient.Metadata,
        storedArtwork: LibraryMediaStoreClient.StoredArtwork?
    ) {
        let metadataTitle = metadata.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let metadataTitle, !metadataTitle.isEmpty {
            title = metadataTitle
        } else {
            title =
                URL(fileURLWithPath: stagedAudio.sourceName)
                .deletingPathExtension()
                .lastPathComponent
        }

        self.init(
            id: storedAudio.trackID,
            audioReference: storedAudio.reference,
            contentIdentity: stagedAudio.contentIdentity,
            title: title,
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
}

private extension Library.Item {
    init(
        catalogEntry: LibraryCatalogClient.Entry,
        storedAudio: LibraryMediaStoreClient.StoredAudio,
        artworkURL: URL?
    ) {
        self.init(
            track: Track(
                id: catalogEntry.id,
                title: catalogEntry.title,
                artistName: catalogEntry.artistName,
                albumTitle: catalogEntry.albumTitle,
                artworkURL: artworkURL,
                duration: catalogEntry.duration,
                playbackURL: storedAudio.url
            ),
            contentIdentity: catalogEntry.contentIdentity,
            addedAt: catalogEntry.addedAt
        )
    }
}
