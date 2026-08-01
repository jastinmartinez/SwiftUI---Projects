import Foundation

/// Defines batch progress, terminal summaries, and delegate values coordinated
/// by `LibraryImportReducer`.
///
/// These models describe import state and communication without importing one
/// item, mutating the confirmed Library, invoking clients, or rendering UI.
extension LibraryImportReducer {
    /// One source that could not complete every import operation.
    struct Issue: Equatable, Identifiable, Sendable {
        let id: UUID
        let sourceName: String
        let failure: LibraryFailure
    }

    /// The current counts and next source in a sequential import batch.
    struct Progress: Equatable, Sendable {
        let sources: [URL]
        var nextIndex: Int
        var importedCount: Int
        var duplicateCount: Int
        var issues: [Issue]
    }

    /// The durable user-facing facts retained after a batch stops.
    struct Summary: Equatable, Sendable {
        let importedCount: Int
        let duplicateCount: Int
        let issues: [Issue]
    }

    /// Describes the user-visible lifecycle of one Library import batch.
    ///
    /// The value groups progress and terminal summaries for the import feature.
    /// It performs no file operations, persistence, Library mutation,
    /// cancellation, navigation, localization, or rendering.
    enum Lifecycle: Equatable, Sendable {
        case importing(Progress)
        case completed(Summary)
        case cancelled(Summary)
    }

    enum Phase: Equatable {
        case ready
        case cancellationRequested
        case completed
    }

    struct Completion: Equatable, Sendable {
        let library: Library
        let catalog: LibraryCatalogClient.Snapshot
        let summary: Summary
    }

    enum Delegate: Equatable {
        case completed(Completion)
        case cancelled(Completion)
    }
}
