import ComposableArchitecture
import Foundation

/// Recovers one Library item from catalog membership and managed audio.
///
/// The reducer owns only the temporary work required to produce one playable
/// `Library.Item` and its catalog entry. It reports whether that work changed
/// the catalog, leaving batch iteration, catalog replacement, and confirmed
/// Library ownership to its parent.
@Reducer
struct LibraryItemRecoveryReducer {
    enum Source: Equatable {
        case catalogEntry(
            LibraryCatalogClient.Entry,
            storedAudio: LibraryMediaStoreClient.StoredAudio
        )
        case uncatalogedAudio(LibraryMediaStoreClient.StoredAudio)
    }

    @ObservableState
    struct State: Equatable {
        let source: Source
        var phase = Phase.ready
    }

    enum Phase: Equatable {
        case ready
        case resolvingArtwork(
            LibraryCatalogClient.Entry,
            LibraryMediaStoreClient.StoredAudio
        )
        case readingMissingArtwork(
            LibraryCatalogClient.Entry,
            LibraryMediaStoreClient.StoredAudio
        )
        case storingRecoveredArtwork(
            LibraryCatalogClient.Entry,
            LibraryMediaStoreClient.StoredAudio
        )
        case identifyingAudio(LibraryMediaStoreClient.StoredAudio)
        case readingMetadata(
            LibraryMediaStoreClient.StoredAudio,
            Library.ContentIdentity
        )
        case storingNewArtwork(
            LibraryMediaStoreClient.StoredAudio,
            Library.ContentIdentity,
            AudioMetadataClient.Metadata
        )
        case completed
    }

    struct RecoveredItem: Equatable {
        let catalogEntry: LibraryCatalogClient.Entry
        let libraryItem: Library.Item

        init(
            catalogEntry: LibraryCatalogClient.Entry,
            libraryItem: Library.Item
        ) {
            self.catalogEntry = catalogEntry
            self.libraryItem = libraryItem
        }

        init(
            catalogEntry: LibraryCatalogClient.Entry,
            storedAudio: LibraryMediaStoreClient.StoredAudio,
            artworkURL: URL?
        ) {
            self.init(
                catalogEntry: catalogEntry,
                libraryItem: Library.Item(
                    catalogEntry: catalogEntry,
                    storedAudio: storedAudio,
                    artworkURL: artworkURL
                )
            )
        }

        init(
            storedAudio: LibraryMediaStoreClient.StoredAudio,
            contentIdentity: Library.ContentIdentity,
            metadata: AudioMetadataClient.Metadata,
            storedArtwork: LibraryMediaStoreClient.StoredArtwork?
        ) {
            let catalogEntry = LibraryCatalogClient.Entry(
                storedAudio: storedAudio,
                contentIdentity: contentIdentity,
                metadata: metadata,
                storedArtwork: storedArtwork
            )
            self.init(
                catalogEntry: catalogEntry,
                storedAudio: storedAudio,
                artworkURL: storedArtwork?.url
            )
        }
    }

    enum Completion: Equatable {
        case catalogUnchanged(RecoveredItem)
        case catalogChanged(RecoveredItem)
    }

    enum Delegate: Equatable {
        case completed(Completion)
        case failed(LibraryFailure)
    }

    enum Action: Equatable {
        case start
        case artworkResolutionCompleted(Result<URL, LibraryFailure>)
        case missingArtworkMetadataRead(
            Result<AudioMetadataClient.Metadata, LibraryFailure>
        )
        case recoveredArtworkStorageCompleted(
            Result<LibraryMediaStoreClient.StoredArtwork, LibraryFailure>
        )
        case audioIdentificationCompleted(
            Result<Library.ContentIdentity, LibraryFailure>
        )
        case audioMetadataRead(
            Result<AudioMetadataClient.Metadata, LibraryFailure>
        )
        case newArtworkStorageCompleted(
            Result<LibraryMediaStoreClient.StoredArtwork, LibraryFailure>
        )
        case delegate(Delegate)
    }

    @Dependency(\.audioMetadata) private var audioMetadata
    @Dependency(\.libraryMediaStore) private var libraryMediaStore

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                guard state.phase == .ready else { return .none }

                switch state.source {
                case let .catalogEntry(catalogEntry, storedAudio):
                    if let artworkReference = catalogEntry.artworkReference {
                        state.phase = .resolvingArtwork(
                            catalogEntry,
                            storedAudio
                        )
                        return .run { send in
                            let result = await libraryMediaStore.resolveFileURL(
                                artworkReference
                            )
                            await send(.artworkResolutionCompleted(result))
                        }
                    }
                    state.phase = .completed
                    return .send(
                        .delegate(
                            .completed(
                                .catalogUnchanged(
                                    RecoveredItem(
                                        catalogEntry: catalogEntry,
                                        storedAudio: storedAudio,
                                        artworkURL: nil
                                    )
                                )
                            )
                        )
                    )

                case let .uncatalogedAudio(storedAudio):
                    state.phase = .identifyingAudio(storedAudio)
                    return .run { send in
                        let result = await libraryMediaStore.identifyAudio(
                            storedAudio.url
                        )
                        await send(.audioIdentificationCompleted(result))
                    }
                }

            case let .artworkResolutionCompleted(result):
                guard
                    case let .resolvingArtwork(
                        catalogEntry,
                        storedAudio
                    ) = state.phase
                else {
                    return .none
                }

                switch result {
                case let .success(artworkURL):
                    state.phase = .completed
                    return .send(
                        .delegate(
                            .completed(
                                .catalogUnchanged(
                                    RecoveredItem(
                                        catalogEntry: catalogEntry,
                                        storedAudio: storedAudio,
                                        artworkURL: artworkURL
                                    )
                                )
                            )
                        )
                    )

                case .failure:
                    let recoveredEntry = catalogEntry.withArtworkReference(nil)
                    state.phase = .readingMissingArtwork(
                        recoveredEntry,
                        storedAudio
                    )
                    return .run { send in
                        let result = await audioMetadata.read(storedAudio.url)
                        await send(.missingArtworkMetadataRead(result))
                    }
                }

            case let .missingArtworkMetadataRead(result):
                guard
                    case let .readingMissingArtwork(
                        recoveredEntry,
                        storedAudio
                    ) = state.phase
                else {
                    return .none
                }

                switch result {
                case let .success(metadata):
                    guard let artworkData = metadata.artworkData else {
                        state.phase = .completed
                        return .send(
                            .delegate(
                                .completed(
                                    .catalogChanged(
                                        RecoveredItem(
                                            catalogEntry: recoveredEntry,
                                            storedAudio: storedAudio,
                                            artworkURL: nil
                                        )
                                    )
                                )
                            )
                        )
                    }

                    state.phase = .storingRecoveredArtwork(
                        recoveredEntry,
                        storedAudio
                    )
                    return .run { send in
                        let result = await libraryMediaStore.storeArtwork(
                            artworkData,
                            recoveredEntry.id
                        )
                        await send(.recoveredArtworkStorageCompleted(result))
                    }

                case .failure:
                    state.phase = .completed
                    return .send(
                        .delegate(
                            .completed(
                                .catalogChanged(
                                    RecoveredItem(
                                        catalogEntry: recoveredEntry,
                                        storedAudio: storedAudio,
                                        artworkURL: nil
                                    )
                                )
                            )
                        )
                    )
                }

            case let .recoveredArtworkStorageCompleted(result):
                guard
                    case let .storingRecoveredArtwork(
                        recoveredEntry,
                        storedAudio
                    ) = state.phase
                else {
                    return .none
                }

                let catalogEntry: LibraryCatalogClient.Entry
                let artworkURL: URL?
                switch result {
                case let .success(storedArtwork):
                    catalogEntry = recoveredEntry.withArtworkReference(
                        storedArtwork.reference
                    )
                    artworkURL = storedArtwork.url
                case .failure:
                    catalogEntry = recoveredEntry
                    artworkURL = nil
                }
                state.phase = .completed
                return .send(
                    .delegate(
                        .completed(
                            .catalogChanged(
                                RecoveredItem(
                                    catalogEntry: catalogEntry,
                                    storedAudio: storedAudio,
                                    artworkURL: artworkURL
                                )
                            )
                        )
                    )
                )

            case let .audioIdentificationCompleted(result):
                guard
                    case let .identifyingAudio(storedAudio) = state.phase
                else {
                    return .none
                }

                switch result {
                case let .success(contentIdentity):
                    state.phase = .readingMetadata(
                        storedAudio,
                        contentIdentity
                    )
                    return .run { send in
                        let result = await audioMetadata.read(storedAudio.url)
                        await send(.audioMetadataRead(result))
                    }
                case let .failure(failure):
                    state.phase = .completed
                    return .send(.delegate(.failed(failure)))
                }

            case let .audioMetadataRead(result):
                guard
                    case let .readingMetadata(
                        storedAudio,
                        contentIdentity
                    ) = state.phase
                else {
                    return .none
                }

                switch result {
                case let .success(metadata):
                    if let artworkData = metadata.artworkData {
                        state.phase = .storingNewArtwork(
                            storedAudio,
                            contentIdentity,
                            metadata
                        )
                        return .run { send in
                            let result = await libraryMediaStore.storeArtwork(
                                artworkData,
                                storedAudio.trackID
                            )
                            await send(.newArtworkStorageCompleted(result))
                        }
                    }

                    let recoveredItem = RecoveredItem(
                        storedAudio: storedAudio,
                        contentIdentity: contentIdentity,
                        metadata: metadata,
                        storedArtwork: nil
                    )
                    state.phase = .completed
                    return .send(
                        .delegate(
                            .completed(
                                .catalogChanged(recoveredItem)
                            )
                        )
                    )

                case let .failure(failure):
                    state.phase = .completed
                    return .send(.delegate(.failed(failure)))
                }

            case let .newArtworkStorageCompleted(result):
                guard
                    case let .storingNewArtwork(
                        storedAudio,
                        contentIdentity,
                        metadata
                    ) = state.phase
                else {
                    return .none
                }

                let storedArtwork: LibraryMediaStoreClient.StoredArtwork?
                switch result {
                case let .success(value):
                    storedArtwork = value
                case .failure:
                    storedArtwork = nil
                }
                let recoveredItem = RecoveredItem(
                    storedAudio: storedAudio,
                    contentIdentity: contentIdentity,
                    metadata: metadata,
                    storedArtwork: storedArtwork
                )
                state.phase = .completed
                return .send(
                    .delegate(
                        .completed(
                            .catalogChanged(recoveredItem)
                        )
                    )
                )

            case .delegate:
                return .none
            }
        }
    }
}

private extension LibraryCatalogClient.Entry {
    /// Creates catalog membership from one managed audio file and its metadata.
    init(
        storedAudio: LibraryMediaStoreClient.StoredAudio,
        contentIdentity: Library.ContentIdentity,
        metadata: AudioMetadataClient.Metadata,
        storedArtwork: LibraryMediaStoreClient.StoredArtwork?
    ) {
        let metadataTitle = metadata.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let filenameTitle = storedAudio.url
            .deletingPathExtension()
            .lastPathComponent
        let title: String
        if let metadataTitle, !metadataTitle.isEmpty {
            title = metadataTitle
        } else {
            title = filenameTitle
        }

        self.init(
            id: storedAudio.trackID,
            audioReference: storedAudio.reference,
            contentIdentity: contentIdentity,
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

    /// Returns this membership with one replacement artwork reference.
    func withArtworkReference(
        _ artworkReference: LibraryMediaStoreClient.FileReference?
    ) -> Self {
        Self(
            id: id,
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
}

private extension Library.Item {
    /// Creates a playable Library item from catalog membership and managed audio.
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
