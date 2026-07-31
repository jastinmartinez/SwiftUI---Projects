import Foundation

/// Performs root-confined filesystem operations for Library infrastructure.
///
/// This concrete value owns managed path derivation, containment validation,
/// and the narrow synchronous file operations shared by Library adapters. It
/// does not coordinate imports, interpret metadata or catalog schemas, map
/// failures into product policy, or manage security-scoped resource lifetime.
/// `FileManager` remains an operation-local infrastructure detail.
struct ManagedLibraryFileSystem: Sendable {
    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    var catalogURL: URL {
        rootURL.appending(path: "catalog.json")
    }

    /// Creates the opaque managed-audio reference for a Library-owned track.
    ///
    /// - Parameters:
    ///   - trackID: A Library-qualified UUID track identity.
    ///   - fileExtension: The normalized extension for the managed audio.
    /// - Returns: A contained relative reference, or `nil` for invalid input.
    func audioReference(
        for trackID: TrackID,
        fileExtension: LibraryMediaStoreClient.FileExtension
    ) -> LibraryMediaStoreClient.FileReference? {
        guard
            trackID.providerID == .library,
            UUID(uuidString: trackID.nativeID) != nil,
            isSafe(fileExtension: fileExtension.rawValue)
        else {
            return nil
        }
        return LibraryMediaStoreClient.FileReference(
            rawValue: "Audio/\(trackID.nativeID).\(fileExtension.rawValue)"
        )
    }

    /// Resolves an opaque relative reference only when it remains under root.
    func resolve(
        _ reference: LibraryMediaStoreClient.FileReference
    ) -> URL? {
        let components = reference.rawValue.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard
            !components.isEmpty,
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return nil
        }
        let resolvedURL = components.reduce(rootURL) { partialURL, component in
            partialURL.appending(path: String(component))
        }
        return try? validatedManagedURL(resolvedURL)
    }

    func copyItem(from sourceURL: URL, to managedURL: URL) throws {
        let managedURL = try validatedManagedURL(managedURL)
        try FileManager().copyItem(at: sourceURL, to: managedURL)
    }

    func moveItem(
        from managedSourceURL: URL,
        to managedDestinationURL: URL
    ) throws {
        let sourceURL = try validatedManagedURL(managedSourceURL)
        let destinationURL = try validatedManagedURL(managedDestinationURL)
        try FileManager().moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItemIfPresent(at managedURL: URL) throws {
        let managedURL = try validatedManagedURL(managedURL)
        let fileManager = FileManager()
        guard fileManager.fileExists(atPath: managedURL.path) else { return }
        try fileManager.removeItem(at: managedURL)
    }

    func creationDate(at managedURL: URL) throws -> Date {
        let managedURL = try validatedManagedURL(managedURL)
        let attributes = try FileManager().attributesOfItem(
            atPath: managedURL.path
        )
        guard let creationDate = attributes[.creationDate] as? Date else {
            throw Error.missingCreationDate
        }
        return creationDate
    }

    func readDataIfPresent(at managedURL: URL) throws -> Data? {
        let managedURL = try validatedManagedURL(managedURL)
        guard FileManager().fileExists(atPath: managedURL.path) else {
            return nil
        }
        return try Data(contentsOf: managedURL)
    }

    /// Writes complete data without exposing a partial destination or
    /// destroying the previously readable file when the operation fails.
    func writeData(_ data: Data, to managedURL: URL) throws {
        let managedURL = try validatedManagedURL(managedURL)
        try data.write(to: managedURL, options: .atomic)
    }

    private func isSafe(fileExtension: String) -> Bool {
        !fileExtension.isEmpty
            && fileExtension.unicodeScalars.allSatisfy(
                CharacterSet.alphanumerics.contains
            )
    }

    private func validatedManagedURL(_ candidateURL: URL) throws -> URL {
        guard rootURL.isFileURL, candidateURL.isFileURL else {
            throw Error.unmanagedURL
        }
        let standardizedCandidateURL = candidateURL.standardizedFileURL
        let resolvedRootComponents = rootURL.resolvingSymlinksInPath()
            .pathComponents
        let resolvedCandidateComponents =
            standardizedCandidateURL
                .resolvingSymlinksInPath()
                .pathComponents
        guard resolvedCandidateComponents.starts(with: resolvedRootComponents)
        else {
            throw Error.unmanagedURL
        }
        return standardizedCandidateURL
    }
}

extension ManagedLibraryFileSystem {
    var audioDirectoryURL: URL {
        rootURL.appending(path: "Audio")
    }

    var artworkDirectoryURL: URL {
        rootURL.appending(path: "Artwork")
    }

    var stagingDirectoryURL: URL {
        rootURL.appending(path: "Staging")
    }

    func createDirectory(at managedURL: URL) throws {
        let managedURL = try validatedManagedURL(managedURL)
        try FileManager().createDirectory(
            at: managedURL,
            withIntermediateDirectories: true
        )
    }

    func contentsOfDirectory(at managedURL: URL) throws -> [URL] {
        let managedURL = try validatedManagedURL(managedURL)
        return try FileManager()
            .contentsOfDirectory(
                at: managedURL,
                includingPropertiesForKeys: nil
            )
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

extension ManagedLibraryFileSystem {
    private enum Error: Swift.Error {
        case unmanagedURL
        case missingCreationDate
    }
}
