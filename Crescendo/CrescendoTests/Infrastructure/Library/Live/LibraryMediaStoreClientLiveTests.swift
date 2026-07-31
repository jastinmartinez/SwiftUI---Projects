import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

/// Proves the filesystem-backed media-store lifecycle at its client boundary.
///
/// The suite injects security-scoped copying and a temporary managed root. It
/// does not exercise reducers, catalog persistence, metadata, or Foundation's
/// security-scope implementation.
struct LibraryMediaStoreClientLiveTests {
    @Test
    func stagingReturnsTheCopiedFilesIdentityAndAvoidsNameCollisions() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        let copiedData = Data("abc".utf8)
        let copies = LockIsolated<[(URL, URL)]>([])
        let copyClient = SecurityScopedFileCopyClient(
            copy: { sourceURL, destinationURL in
                copies.withValue { $0.append((sourceURL, destinationURL)) }
                do {
                    try copiedData.write(to: destinationURL)
                    return .success(())
                } catch {
                    return .failure(.fileWriteFailed)
                }
            }
        )
        let client = LibraryMediaStoreClient.live(
            fileSystem: fileSystem,
            securityScopedFileCopy: copyClient
        )
        let sourceURL = URL(fileURLWithPath: "/external/Song.M4A")

        let first = try await client.stageAudio(sourceURL).get()
        let second = try await client.stageAudio(sourceURL).get()

        #expect(first.sourceName == "Song.M4A")
        #expect(first.fileExtension == .init(rawValue: "m4a"))
        #expect(
            first.contentIdentity
                == .init(
                    rawValue: "ba7816bf8f01cfea414140de5dae2223"
                        + "b00361a396177a9cb410ff61f20015ad"
                )
        )
        #expect(first.temporaryURL != second.temporaryURL)
        #expect(
            copies.value.map(\.0) == [sourceURL, sourceURL]
        )
        #expect(
            copies.value.map {
                $0.1.deletingLastPathComponent().pathComponents
            }
                == [
                    fileSystem.stagingDirectoryURL.pathComponents,
                    fileSystem.stagingDirectoryURL.pathComponents,
                ]
        )
    }

    @Test
    func failedStagingRemovesThePartialManagedCopy() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        let copyClient = SecurityScopedFileCopyClient(
            copy: { _, destinationURL in
                try? Data("partial".utf8).write(to: destinationURL)
                return .failure(.accessDenied)
            }
        )
        let client = LibraryMediaStoreClient.live(
            fileSystem: fileSystem,
            securityScopedFileCopy: copyClient
        )

        let result = await client.stageAudio(
            URL(fileURLWithPath: "/external/song.m4a")
        )

        #expect(result == .failure(.accessDenied))
        #expect(
            try fileSystem.contentsOfDirectory(
                at: fileSystem.stagingDirectoryURL
            ).isEmpty
        )
    }

    @Test
    func cancelledStagingRemovesThePartialManagedCopy() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        let suspendedCopy =
            SuspendedOperationProbe<Result<Void, LibraryFailure>>()
        let copyClient = SecurityScopedFileCopyClient(
            copy: { _, destinationURL in
                do {
                    try Data("partial".utf8).write(to: destinationURL)
                    return try await suspendedCopy.run()
                } catch {
                    return .failure(.fileWriteFailed)
                }
            }
        )
        let client = LibraryMediaStoreClient.live(
            fileSystem: fileSystem,
            securityScopedFileCopy: copyClient
        )
        let task = Task {
            await client.stageAudio(
                URL(fileURLWithPath: "/external/song.m4a")
            )
        }
        await suspendedCopy.waitUntilStarted()

        task.cancel()
        await suspendedCopy.waitUntilCancelled()
        _ = await task.value

        #expect(
            try fileSystem.contentsOfDirectory(
                at: fileSystem.stagingDirectoryURL
            ).isEmpty
        )
    }

    @Test
    func storingListsAndResolvesThePromotedAudio() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        try fileSystem.createDirectory(at: fileSystem.stagingDirectoryURL)
        let temporaryURL = fileSystem.stagingDirectoryURL
            .appending(path: "staged.m4a")
        try fileSystem.writeData(Data("audio".utf8), to: temporaryURL)
        let stagedAudio = LibraryMediaStoreClient.StagedAudio(
            sourceName: "Song.m4a",
            temporaryURL: temporaryURL,
            fileExtension: .init(rawValue: "m4a"),
            contentIdentity: .init(rawValue: "identity")
        )
        let trackID = TrackID(
            providerID: .library,
            nativeID: "01234567-89AB-CDEF-0123-456789ABCDEF"
        )
        let client = LibraryMediaStoreClient.live(
            fileSystem: fileSystem,
            securityScopedFileCopy: unusedCopyClient()
        )

        let storedAudio = try await client.storeAudio(
            stagedAudio,
            trackID
        ).get()
        let listedAudio = try await client.listStoredAudio().get()
        let resolvedURL = try await client.resolveFileURL(
            storedAudio.reference
        ).get()
        await client.discardStagedAudio(stagedAudio)
        await client.discardStagedAudio(stagedAudio)

        #expect(storedAudio.trackID == trackID)
        #expect(
            storedAudio.reference.rawValue
                == "Audio/\(trackID.nativeID).m4a"
        )
        #expect(
            storedAudio.url
                == fileSystem.audioDirectoryURL.appending(
                    path: "\(trackID.nativeID).m4a"
                )
        )
        #expect(listedAudio == [storedAudio])
        #expect(resolvedURL == storedAudio.url)
        #expect(try fileSystem.readDataIfPresent(at: temporaryURL) == nil)
    }

    @Test
    func malformedManagedAudioFailsListing() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        try fileSystem.createDirectory(at: fileSystem.audioDirectoryURL)
        try fileSystem.writeData(
            Data("audio".utf8),
            to: fileSystem.audioDirectoryURL.appending(path: "not-a-uuid.m4a")
        )
        let client = LibraryMediaStoreClient.live(
            fileSystem: fileSystem,
            securityScopedFileCopy: unusedCopyClient()
        )

        let result = await client.listStoredAudio()

        #expect(result == .failure(.invalidManagedFile))
    }

    @Test
    func artworkUsesAnOpaqueManagedReference() async throws {
        let (fileSystem, rootURL) = try makeFileSystem()
        defer { try? fileSystem.removeItemIfPresent(at: rootURL) }
        let trackID = TrackID(
            providerID: .library,
            nativeID: "01234567-89AB-CDEF-0123-456789ABCDEF"
        )
        let artworkData = Data([0xCA, 0xFE])
        let client = LibraryMediaStoreClient.live(
            fileSystem: fileSystem,
            securityScopedFileCopy: unusedCopyClient()
        )

        let storedArtwork = try await client.storeArtwork(
            artworkData,
            trackID
        ).get()

        #expect(
            storedArtwork.reference.rawValue
                == "Artwork/\(trackID.nativeID)"
        )
        #expect(
            try fileSystem.readDataIfPresent(at: storedArtwork.url)
                == artworkData
        )
        #expect(
            await client.storeArtwork(
                artworkData,
                TrackID(providerID: .jamendo, nativeID: trackID.nativeID)
            ) == .failure(.invalidManagedFile)
        )
    }

    private func makeFileSystem() throws -> (
        fileSystem: ManagedLibraryFileSystem,
        rootURL: URL
    ) {
        let rootURL = URL.temporaryDirectory
            .appending(path: "LibraryMediaStoreClientLiveTests-\(UUID().uuidString)")
        let fileSystem = ManagedLibraryFileSystem(rootURL: rootURL)
        try fileSystem.createDirectory(at: rootURL)
        return (fileSystem, rootURL)
    }

    private func unusedCopyClient() -> SecurityScopedFileCopyClient {
        SecurityScopedFileCopyClient(
            copy: { _, _ in
                Issue.record("Unexpected security-scoped copy")
                return .failure(.fileWriteFailed)
            }
        )
    }
}
