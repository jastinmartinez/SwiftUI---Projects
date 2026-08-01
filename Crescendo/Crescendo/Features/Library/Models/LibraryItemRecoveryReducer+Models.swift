import Foundation

/// Defines the source, progress, and outcome values used to recover one Library
/// item.
///
/// The models construct recovered catalog and Library values without invoking
/// clients, iterating the recovery batch, or committing confirmed feature state.
extension LibraryItemRecoveryReducer {
    enum Source: Equatable {
        case catalogEntry(
            LibraryCatalogClient.Entry,
            storedAudio: LibraryMediaStoreClient.StoredAudio
        )
        case uncatalogedAudio(LibraryMediaStoreClient.StoredAudio)
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
