import Foundation

/// Assembles the clients that share Crescendo's managed Library root.
///
/// This application-composition value owns filesystem and catalog wiring. It
/// exposes only reducer-facing clients and the Library search adapter; it does
/// not expose lower-level filesystem or catalog-store infrastructure.
@MainActor
struct LibraryComposition {
    let libraryMediaStore: LibraryMediaStoreClient
    let audioMetadata: AudioMetadataClient
    let libraryCatalog: LibraryCatalogClient
    let librarySearch: ProviderSearchClient

    init(applicationSupportURL: URL) {
        let crescendoSupportURL = applicationSupportURL.appending(
            path: "Crescendo"
        )
        let libraryRootURL = crescendoSupportURL.appending(path: "Library")
        let fileSystem = ManagedLibraryFileSystem(rootURL: libraryRootURL)
        let securityScopedFileCopy = SecurityScopedFileCopyClient.live(
            fileSystem: fileSystem
        )
        let libraryMediaStore = LibraryMediaStoreClient.live(
            fileSystem: fileSystem,
            securityScopedFileCopy: securityScopedFileCopy
        )
        let libraryCatalogStore = LibraryCatalogStore(
            catalogURL: fileSystem.catalogURL,
            catalogFile: LibraryCatalogFileClient.live(
                fileSystem: fileSystem
            )
        )
        let libraryCatalog = LibraryCatalogClient.live(
            store: libraryCatalogStore
        )

        self.libraryMediaStore = libraryMediaStore
        self.audioMetadata = .live()
        self.libraryCatalog = libraryCatalog
        self.librarySearch = .live(
            libraryCatalog: libraryCatalog,
            libraryMediaStore: libraryMediaStore
        )
    }
}
