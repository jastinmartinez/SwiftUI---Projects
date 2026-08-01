import ComposableArchitecture
import Foundation
import IdentifiedCollections

/// Defines the reducer-facing boundary for loading and replacing the Library
/// catalog.
///
/// The client exchanges typed snapshots without exposing JSON, filesystem
/// locations, serialization, recovery policy, import sequencing, playback, or
/// UI retry behavior. Concrete persistence adapters own their storage schema
/// and translate it at this boundary.
struct LibraryCatalogClient: Sendable {
    /// Loads the latest complete catalog snapshot.
    var load: @Sendable () async -> Result<Snapshot, LibraryFailure>

    /// Replaces the complete catalog and returns the confirmed snapshot.
    var replace: @Sendable (Snapshot) async -> Result<Snapshot, LibraryFailure>
}

extension LibraryCatalogClient {
    /// One persisted Library membership exchanged with reducer workflows.
    ///
    /// This contract value is neither a Domain entity nor a storage-format DTO.
    /// A concrete catalog adapter translates its versioned representation into
    /// this value and leaves managed-file resolution to the media-store client.
    struct Entry: Equatable, Identifiable, Sendable {
        let id: TrackID
        let audioReference: LibraryMediaStoreClient.FileReference
        let contentIdentity: Library.ContentIdentity
        let title: String
        let artistName: String?
        let albumTitle: String?
        let albumArtistName: String?
        let duration: TimeInterval?
        let trackNumber: Int?
        let discNumber: Int?
        let artworkReference: LibraryMediaStoreClient.FileReference?
        let addedAt: Date

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

    /// The complete catalog value exchanged in one load or replacement.
    struct Snapshot: Equatable, Sendable {
        let entries: IdentifiedArrayOf<Entry>
    }
}

extension LibraryCatalogClient: DependencyKey {
    static let liveValue = Self(
        load: {
            fatalError("LibraryCatalogClient.load is not configured")
        },
        replace: { _ in
            fatalError("LibraryCatalogClient.replace is not configured")
        }
    )
}

extension DependencyValues {
    var libraryCatalog: LibraryCatalogClient {
        get { self[LibraryCatalogClient.self] }
        set { self[LibraryCatalogClient.self] = newValue }
    }
}
