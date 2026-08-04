import Foundation

extension SecurityScopedFileCopyClient {
    /// Uses Foundation security-scoped resource lifetime around one managed
    /// filesystem copy.
    ///
    /// Access denial and copy failure are mapped into the Library failure
    /// vocabulary. The selected URL is always released before the operation
    /// returns after a successful acquisition.
    ///
    /// - Parameter fileSystem: The root-confined destination copy mechanism.
    /// - Returns: A copy client that brackets each operation with
    ///   security-scoped access.
    static func live(fileSystem: ManagedLibraryFileSystem) -> Self {
        Self(
            copy: { sourceURL, destinationURL in
                guard sourceURL.startAccessingSecurityScopedResource() else {
                    return .failure(.accessDenied)
                }
                defer { sourceURL.stopAccessingSecurityScopedResource() }

                do {
                    try fileSystem.copyItem(
                        from: sourceURL,
                        to: destinationURL
                    )
                    return .success(())
                } catch {
                    return .failure(.fileWriteFailed)
                }
            }
        )
    }
}
