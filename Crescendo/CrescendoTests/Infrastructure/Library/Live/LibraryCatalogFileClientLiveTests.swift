import Foundation
import Testing

@testable import Crescendo

/// Proves raw catalog-byte guarantees without interpreting the JSON schema.
struct LibraryCatalogFileClientLiveTests {
    @Test
    func missingCatalogReadsAsAbsence() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        let client = LibraryCatalogFileClient.live(fileSystem: fileSystem)

        let result = await client.read(fileSystem.catalogURL)

        #expect(result == .success(nil))
    }

    @Test
    func completeWriteCanBeReadBack() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        let client = LibraryCatalogFileClient.live(fileSystem: fileSystem)
        let data = Data("catalog".utf8)

        let writeResult = await client.write(data, fileSystem.catalogURL)
        let readResult = await client.read(fileSystem.catalogURL)

        if case let .failure(failure) = writeResult {
            Issue.record("Unexpected catalog write failure: \(failure)")
        }
        #expect(readResult == .success(data))
    }

    @Test
    func failedWritePreservesThePreviouslyReadableCatalog() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        let client = LibraryCatalogFileClient.live(fileSystem: fileSystem)
        let previousData = Data("previous".utf8)
        _ = await client.write(previousData, fileSystem.catalogURL)

        let failure = await client.write(
            Data("replacement".utf8),
            rootURL.deletingLastPathComponent().appending(path: "outside.json")
        )
        let preserved = await client.read(fileSystem.catalogURL)

        guard case .failure(.catalogWriteFailed) = failure else {
            Issue.record("Expected catalog write failure")
            return
        }
        #expect(preserved == .success(previousData))
    }

    private func makeFileSystem() throws -> (
        fileSystem: ManagedLibraryFileSystem,
        rootURL: URL
    ) {
        let rootURL = URL.temporaryDirectory.appending(
            path: "LibraryCatalogFileClientLiveTests-\(UUID().uuidString)"
        )
        let fileSystem = ManagedLibraryFileSystem(rootURL: rootURL)
        try fileSystem.createDirectory(at: rootURL)
        return (fileSystem, rootURL)
    }
}
