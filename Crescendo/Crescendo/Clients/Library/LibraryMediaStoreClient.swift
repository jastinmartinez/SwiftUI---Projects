import ComposableArchitecture
import Foundation

/// Defines the replaceable boundary for app-managed Library media storage.
///
/// The client stages audio, promotes it into managed storage, stores artwork,
/// lists managed audio, identifies file content, and resolves opaque file
/// references. Import sequencing, metadata extraction, catalog encoding,
/// duplicate policy, playback, and UI retry behavior remain outside this
/// boundary.
struct LibraryMediaStoreClient: Sendable {
    /// Copies external audio into temporary app-owned storage.
    var stageAudio: @Sendable (URL) async -> Result<StagedAudio, LibraryFailure>

    /// Promotes staged audio into the managed location for `TrackID`.
    var storeAudio: @Sendable (StagedAudio, TrackID) async -> Result<StoredAudio, LibraryFailure>

    /// Removes one staged file after completion or rollback.
    var discardStagedAudio: @Sendable (StagedAudio) async -> Void

    /// Lists audio files currently owned by managed storage.
    var listStoredAudio: @Sendable () async -> Result<[StoredAudio], LibraryFailure>

    /// Produces the opaque content identity used by duplicate policy.
    var identifyAudio: @Sendable (URL) async -> Result<Library.ContentIdentity, LibraryFailure>

    /// Stores artwork for the identified track in managed storage.
    var storeArtwork: @Sendable (Data, TrackID) async -> Result<StoredArtwork, LibraryFailure>

    /// Resolves an opaque managed-file reference to a playback-capable URL.
    var resolveFileURL: @Sendable (FileReference) async -> Result<URL, LibraryFailure>
}

extension LibraryMediaStoreClient {
    /// A normalized filename extension exchanged with media-storage adapters.
    struct FileExtension: Equatable, Hashable, Sendable {
        let rawValue: String
    }

    /// An opaque reference to a file owned by the managed-media store.
    ///
    /// Consumers may retain and compare this value, but only the media-store
    /// implementation may interpret it as a storage location.
    struct FileReference: Equatable, Hashable, Sendable {
        let rawValue: String
    }

    /// Audio copied into temporary app-owned storage and ready for promotion.
    struct StagedAudio: Equatable, Sendable {
        let sourceName: String
        let temporaryURL: URL
        let fileExtension: FileExtension
        let contentIdentity: Library.ContentIdentity
    }

    /// Audio confirmed in its durable app-managed storage location.
    struct StoredAudio: Equatable, Sendable {
        let trackID: TrackID
        let reference: FileReference
        let url: URL
        let creationDate: Date
    }

    /// Artwork confirmed in its durable app-managed storage location.
    struct StoredArtwork: Equatable, Sendable {
        let reference: FileReference
        let url: URL
    }
}

extension LibraryMediaStoreClient: DependencyKey {
    static let liveValue = Self(
        stageAudio: { _ in
            fatalError("LibraryMediaStoreClient.stageAudio is not configured")
        },
        storeAudio: { _, _ in
            fatalError("LibraryMediaStoreClient.storeAudio is not configured")
        },
        discardStagedAudio: { _ in
            fatalError(
                "LibraryMediaStoreClient.discardStagedAudio is not configured"
            )
        },
        listStoredAudio: {
            fatalError(
                "LibraryMediaStoreClient.listStoredAudio is not configured"
            )
        },
        identifyAudio: { _ in
            fatalError("LibraryMediaStoreClient.identifyAudio is not configured")
        },
        storeArtwork: { _, _ in
            fatalError("LibraryMediaStoreClient.storeArtwork is not configured")
        },
        resolveFileURL: { _ in
            fatalError(
                "LibraryMediaStoreClient.resolveFileURL is not configured"
            )
        }
    )
}

extension DependencyValues {
    var libraryMediaStore: LibraryMediaStoreClient {
        get { self[LibraryMediaStoreClient.self] }
        set { self[LibraryMediaStoreClient.self] = newValue }
    }
}
