@testable import Filer
import Foundation
import Testing

@Suite struct MediaCacheStoreTests {
    @Test func readReturnsBytesAtOffset() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "photo.jpeg")
        try await store.write(Data([0, 1, 2, 3, 4, 5]), to: url)

        let chunk = try await store.read(at: url, offset: 2, length: 3)

        #expect(chunk == Data([2, 3, 4]))
    }

    @Test func sizeReflectsWrittenBytes() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "photo.jpeg")
        try await store.write(Data([7, 8, 9]), to: url)

        #expect(await store.size(at: url) == 3)
    }

    @Test func sizeIsNilForMissingFile() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(await store.size(at: root.appending(path: "nope.jpeg")) == nil)
    }

    @Test func rangedWriteLandsBytesAtOffsetAndGrowsFile() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "clip.mov")
        try await store.makeFileIfNeeded(at: url)

        try await store.write(Data([1, 2, 3, 4]), to: url, at: 0)
        try await store.write(Data([5, 6]), to: url, at: 4)

        #expect(await store.size(at: url) == 6)
        #expect(try await store.read(at: url, offset: 4, length: 2) == Data([5, 6]))
    }

    @Test func contentsListsWrittenFiles() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appending(path: "imports")
        try await store.write(Data([1]), to: dir.appending(path: "a.jpeg"))
        try await store.write(Data([2]), to: dir.appending(path: "b.jpeg"))

        let names = try await store.contents(of: dir).map(\.lastPathComponent).sorted()

        #expect(names == ["a.jpeg", "b.jpeg"])
    }

    // MARK: - Helpers

    private func makeStore() -> (MediaCacheStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "MediaCacheStoreTests-\(UUID().uuidString)")
        return (MediaCacheStore(), root)
    }
}
