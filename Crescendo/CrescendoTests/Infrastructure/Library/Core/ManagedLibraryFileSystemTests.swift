import Foundation
import Testing

@testable import Crescendo

struct ManagedLibraryFileSystemTests {
    @Test
    func derivesEveryManagedLocationFromTheInjectedRoot() {
        let rootURL = URL(fileURLWithPath: "/container/Library")
        let fileSystem = ManagedLibraryFileSystem(rootURL: rootURL)

        #expect(fileSystem.audioDirectoryURL == rootURL.appending(path: "Audio"))
        #expect(
            fileSystem.artworkDirectoryURL
                == rootURL.appending(path: "Artwork")
        )
        #expect(
            fileSystem.stagingDirectoryURL
                == rootURL.appending(path: "Staging")
        )
        #expect(
            fileSystem.catalogURL
                == rootURL.appending(path: "catalog.json")
        )
    }

    @Test
    func audioReferenceRequiresALibraryUUIDIdentityAndSafeExtension() throws {
        let fileSystem = ManagedLibraryFileSystem(
            rootURL: URL(fileURLWithPath: "/container/Library")
        )
        let nativeID = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let libraryTrackID = TrackID(
            providerID: .library,
            nativeID: nativeID
        )

        let reference = try #require(
            fileSystem.audioReference(
                for: libraryTrackID,
                fileExtension: .init(rawValue: "m4a")
            )
        )

        #expect(reference.rawValue == "Audio/\(nativeID).m4a")
        #expect(
            fileSystem.audioReference(
                for: TrackID(providerID: .jamendo, nativeID: nativeID),
                fileExtension: .init(rawValue: "m4a")
            ) == nil
        )
        #expect(
            fileSystem.audioReference(
                for: TrackID(providerID: .library, nativeID: "not-a-uuid"),
                fileExtension: .init(rawValue: "m4a")
            ) == nil
        )
        #expect(
            fileSystem.audioReference(
                for: libraryTrackID,
                fileExtension: .init(rawValue: "../m4a")
            ) == nil
        )
    }

    @Test
    func resolvesOnlyContainedRelativeReferences() throws {
        let rootURL = URL(fileURLWithPath: "/container/Library")
        let fileSystem = ManagedLibraryFileSystem(rootURL: rootURL)
        let reference = LibraryMediaStoreClient.FileReference(
            rawValue: "Audio/track.m4a"
        )

        let resolvedURL = try #require(fileSystem.resolve(reference))

        #expect(
            resolvedURL
                == rootURL.appending(path: "Audio/track.m4a")
        )
        #expect(fileSystem.resolve(.init(rawValue: "../escape.m4a")) == nil)
        #expect(fileSystem.resolve(.init(rawValue: "/absolute.m4a")) == nil)
        #expect(fileSystem.resolve(.init(rawValue: "")) == nil)
    }

    @Test
    func everyManagedOperationRejectsURLsOutsideTheRoot() {
        let rootURL = URL(fileURLWithPath: "/container/Library")
        let fileSystem = ManagedLibraryFileSystem(rootURL: rootURL)
        let sourceURL = rootURL.appending(path: "source.m4a")
        let destinationURL = rootURL.appending(path: "destination.m4a")
        let outsideURL = rootURL.deletingLastPathComponent()
            .appending(path: "outside.m4a")

        #expect(throws: (any Error).self) {
            try fileSystem.createDirectory(at: outsideURL)
        }
        #expect(throws: (any Error).self) {
            try fileSystem.copyItem(from: sourceURL, to: outsideURL)
        }
        #expect(throws: (any Error).self) {
            try fileSystem.moveItem(
                from: sourceURL,
                to: outsideURL
            )
        }
        #expect(throws: (any Error).self) {
            try fileSystem.moveItem(
                from: outsideURL,
                to: destinationURL
            )
        }
        #expect(throws: (any Error).self) {
            try fileSystem.removeItemIfPresent(at: outsideURL)
        }
        #expect(throws: (any Error).self) {
            try fileSystem.contentsOfDirectory(at: outsideURL)
        }
        #expect(throws: (any Error).self) {
            try fileSystem.creationDate(at: outsideURL)
        }
        #expect(throws: (any Error).self) {
            try fileSystem.readDataIfPresent(at: outsideURL)
        }
        #expect(throws: (any Error).self) {
            try fileSystem.writeData(Data(), to: outsideURL)
        }
    }
}
