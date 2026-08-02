import IdentifiedCollections

/// Defines the navigation, loading, and delegate values coordinated by
/// `LibraryReducer`.
///
/// These values describe feature state and communication without performing
/// loading, recovery, importing, persistence, playback, or presentation.
extension LibraryReducer {
    enum Destination: Hashable, Sendable {
        case songs
    }

    enum LoadStatus: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case recoveredWithCatalogFailure(LibraryFailure)
        case failed(LibraryFailure)
    }

    enum Delegate: Equatable {
        case trackTapped(
            Track,
            loadedTracks: IdentifiedArrayOf<Track>
        )
    }
}

extension LibraryReducer.State {
    /// Whether a new import can start from a fully recovered projection.
    var isImportAvailable: Bool {
        loadStatus == .loaded && !hasActiveImportBatch
    }

    private var hasActiveImportBatch: Bool {
        guard let importBatch else { return false }
        return importBatch.phase != .completed
    }
}
