/// Defines the workflow values produced and consumed by
/// `LibraryRecoveryReducer`.
///
/// These values describe recovery progress and outcomes without iterating the
/// recovery batch, invoking clients, or mutating the confirmed Library.
extension LibraryRecoveryReducer {
    enum Phase: Equatable {
        case ready
        case replacingCatalog(Completion)
        case completed
    }

    /// The complete in-memory projection produced by one recovery run.
    ///
    /// `catalog` remains available even when its replacement failed so a later
    /// import can retry from the recovered projection without another load.
    struct Completion: Equatable, Sendable {
        let library: Library
        let catalog: LibraryCatalogClient.Snapshot
        let catalogWriteFailure: LibraryFailure?
    }

    enum Delegate: Equatable {
        case completed(Completion)
        case failed(LibraryFailure)
    }
}
