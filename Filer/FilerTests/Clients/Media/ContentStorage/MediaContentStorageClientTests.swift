@testable import Filer
import Foundation
import Testing

@Suite struct MediaContentStorageClientTests {
    @Test func valueStoreImportStoresContentWithoutFilesystem() async throws {
        let storage = MediaContentStorageClient.testValue

        let stored = try await storage.storeImport("photo.jpeg", Data([1, 2, 3]))
        let listed = try await storage.listImports()

        #expect(stored.key == "photo.jpeg")
        #expect(stored.size == 3)
        #expect(stored.localURL == URL(fileURLWithPath: "/memory/imports/photo.jpeg"))
        #expect(listed.map(\.key) == ["photo.jpeg"])
        #expect(listed.map(\.size) == [3])
    }

    @Test func valueDownloadTargetUsesDownloadsLocationWithoutFilesystem() async throws {
        let storage = MediaContentStorageClient.testValue

        _ = try await storage.storeImport("same.jpeg", Data([1]))
        let target = try await storage.prepareDownloadTarget("same.jpeg")
        try await storage.writeDownload(target.key, Data([2]), 0)

        #expect(target.key == "same.jpeg")
        #expect(target.localURL == URL(fileURLWithPath: "/memory/downloads/same.jpeg"))
        #expect(try await storage.listImports().map(\.key) == ["same.jpeg"])
        #expect(try await storage.listImports().map(\.size) == [1])
    }

    @Test func valueRemoveImportDeletesOnlyImportWithoutFilesystem() async throws {
        let storage = MediaContentStorageClient.testValue

        _ = try await storage.storeImport("same.jpeg", Data([1]))
        let target = try await storage.prepareDownloadTarget("same.jpeg")
        try await storage.writeDownload(target.key, Data([2]), 0)

        try await storage.removeImport("same.jpeg")

        #expect(try await storage.listImports().isEmpty)
        #expect(target.localURL == URL(fileURLWithPath: "/memory/downloads/same.jpeg"))
    }

    @Test func valueWriteDownloadAcceptsOffsetsWithoutFilesystem() async throws {
        let storage = MediaContentStorageClient.testValue

        let target = try await storage.prepareDownloadTarget("movie.mov")
        try await storage.writeDownload(target.key, Data([1, 2]), 0)
        try await storage.writeDownload(target.key, Data([3]), 2)

        #expect(target.localURL == URL(fileURLWithPath: "/memory/downloads/movie.mov"))
    }

    @Test func valueWriteDownloadFailsWhenDownloadWasNotPrepared() async throws {
        let storage = MediaContentStorageClient.testValue

        await #expect(throws: MediaContentStorageClient.MissingContent(key: "movie.mov")) {
            try await storage.writeDownload("movie.mov", Data([1]), 0)
        }
    }

    @Test func valuePrepareDownloadTargetPreservesExistingDownloadWithoutFilesystem() async throws {
        let storage = MediaContentStorageClient.testValue

        let first = try await storage.prepareDownloadTarget("movie.mov")
        try await storage.writeDownload(first.key, Data([1, 2, 3]), 0)
        let second = try await storage.prepareDownloadTarget("movie.mov")

        #expect(second.localURL == URL(fileURLWithPath: "/memory/downloads/movie.mov"))
        #expect(try await storage.downloadOffset(second.key) == 3)
    }

    @Test func valuePrepareDownloadTargetCreatesEmptyDownloadWithoutFilesystem() async throws {
        let storage = MediaContentStorageClient.testValue

        let target = try await storage.prepareDownloadTarget("clip.mov")

        #expect(target.localURL == URL(fileURLWithPath: "/memory/downloads/clip.mov"))
        #expect(try await storage.downloadOffset(target.key) == 0)
    }

    @Test func valueUploadSourceReturnsDeterministicMemoryURLWithoutFilesystem() async throws {
        let storage = MediaContentStorageClient.testValue

        _ = try await storage.storeImport("photo.jpeg", Data([7, 8, 9]))
        let source = try await storage.importUploadSource("photo.jpeg")

        #expect(source.localURL == URL(fileURLWithPath: "/memory/imports/photo.jpeg"))
        #expect(source.size == 3)
    }

    @Test func valueProvidesFreshStorageForEachAccess() async throws {
        let first = MediaContentStorageClient.testValue
        _ = try await first.storeImport("photo.jpeg", Data([1]))

        let second = MediaContentStorageClient.testValue

        #expect(try await second.listImports().isEmpty)
    }

    @Test func liveAcceptsInjectedFileStore() {
        let fileStore = MediaContentFileStore(
            root: URL(fileURLWithPath: "/memory"),
            fileManager: .default
        )
        _ = MediaContentStorageClient.live(fileStore: fileStore)
    }
}
