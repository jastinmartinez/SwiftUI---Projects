import Foundation

extension LibraryCatalogFileClient {
    /// Uses the managed Library filesystem to satisfy raw catalog-byte access.
    ///
    /// Schema interpretation and catalog serialization remain in
    /// `LibraryCatalogStore`; this adapter maps filesystem failures only.
    static func live(fileSystem: ManagedLibraryFileSystem) -> Self {
        Self(
            read: { catalogURL in
                do {
                    return try .success(
                        fileSystem.readDataIfPresent(at: catalogURL)
                    )
                } catch {
                    return .failure(.catalogReadFailed)
                }
            },
            write: { data, catalogURL in
                do {
                    try fileSystem.createDirectory(
                        at: catalogURL.deletingLastPathComponent()
                    )
                    try fileSystem.writeData(data, to: catalogURL)
                    return .success(())
                } catch {
                    return .failure(.catalogWriteFailed)
                }
            }
        )
    }
}
