import Foundation

/// Defines one temporary-access copy operation for externally selected files.
///
/// The client owns the requirement that security-scoped access is held only
/// while one file is copied into app-managed storage. It does not fingerprint,
/// promote, catalog, or retain access to the selected resource.
struct SecurityScopedFileCopyClient: Sendable {
    /// Copies one external file into a managed destination before releasing
    /// temporary access.
    let copy: @Sendable (URL, URL) async -> Result<Void, LibraryFailure>
}
