/// Defines the progress and outcome values used to import one Library item.
///
/// These models retain operation inputs and results without invoking clients,
/// iterating an import batch, or committing confirmed Library state.
extension LibraryItemImportReducer {
    enum Phase: Equatable {
        case ready
        case staging
        case readingMetadata(
            stagedAudio: LibraryMediaStoreClient.StagedAudio,
            trackID: TrackID
        )
        case discardingDuplicate(
            stagedAudio: LibraryMediaStoreClient.StagedAudio
        )
        case discardingFailedImport(
            stagedAudio: LibraryMediaStoreClient.StagedAudio,
            failure: LibraryFailure
        )
        case storingAudio(
            stagedAudio: LibraryMediaStoreClient.StagedAudio,
            trackID: TrackID,
            metadata: AudioMetadataClient.Metadata
        )
        case storingArtwork(
            stagedAudio: LibraryMediaStoreClient.StagedAudio,
            storedAudio: LibraryMediaStoreClient.StoredAudio,
            metadata: AudioMetadataClient.Metadata
        )
        case preparingCatalog(
            stagedAudio: LibraryMediaStoreClient.StagedAudio,
            storedAudio: LibraryMediaStoreClient.StoredAudio,
            metadata: AudioMetadataClient.Metadata,
            storedArtwork: LibraryMediaStoreClient.StoredArtwork?
        )
        case replacingCatalog(
            item: Library.Item,
            catalog: LibraryCatalogClient.Snapshot
        )
        case cancelling(stagedAudio: LibraryMediaStoreClient.StagedAudio)
        case completed
    }

    struct ImportedItem: Equatable, Sendable {
        let item: Library.Item
        let catalog: LibraryCatalogClient.Snapshot
        let issues: [LibraryImportReducer.Issue]
    }

    enum Delegate: Equatable {
        case imported(ImportedItem)
        case duplicate
        case failed(LibraryImportReducer.Issue)
        case cancelled
    }
}
