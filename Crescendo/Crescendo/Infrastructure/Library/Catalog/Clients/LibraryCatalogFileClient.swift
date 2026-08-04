import Foundation

/// Defines raw catalog-byte access for the actor-backed catalog store.
///
/// This client owns complete reads and crash-safe writes without interpreting
/// JSON, versions, records, recovery policy, or reducer state. Its operations
/// remain explicit so tests can replace disk access without replacing catalog
/// serialization.
struct LibraryCatalogFileClient: Sendable {
    /// Reads the complete catalog bytes, or returns `nil` when no file exists.
    let read: @Sendable (URL) async -> Result<Data?, LibraryFailure>

    /// Creates or overwrites the catalog without exposing partial data or
    /// destroying the previously readable catalog when the operation fails.
    let write: @Sendable (Data, URL) async -> Result<Void, LibraryFailure>
}
