import ComposableArchitecture
@testable import Filer
import PhotosUI
import Testing

@MainActor
@Suite(.serialized)
struct MediaImportFeatureTests {
    // `PhotosPickerItem` has no public initializer, so we cannot build `.picked([nonEmpty])`
    // in a unit test. We drive the loading lifecycle by sending `.loaded(…)` / `.failed(…)`
    // directly and assert the `phase` transitions + the `.delegate(.imported)` emission.
    // The `.picked → .loading` entry edge is covered by the Task 21 manual checklist.

    @Test func loadedPayloadsRemoveExpiredThenStoreAndDelegateImported() async {
        let loaded = Self.payload("a.jpeg")
        let cached = Self.media(from: loaded)
        let events = LockedBox<[String]>([])

        let store = TestStore(initialState: MediaImportFeature.State(phase: .loading)) {
            MediaImportFeature()
        } withDependencies: {
            $0.mediaImport = MediaImportClient()
            $0.mediaImportStore = MediaImportStoreClient(
                store: { payload in
                    events.mutate { $0.append("store:\(payload.metadata.id)") }
                    return cached
                },
                removeExpired: {
                    events.mutate { $0.append("removeExpired") }
                }
            )
        }

        await store.send(.loaded([loaded]))
        await store.receive(\.cached, [cached]) {
            $0.phase = .idle
        }
        await store.receive(\.delegate.imported, [cached])

        #expect(events.value == ["removeExpired", "store:a.jpeg"])
    }

    @Test func cachedReturnsToIdleAndDelegatesImported() async {
        let loaded = [Self.media("a.jpg"), Self.media("b.jpg")]

        let store = TestStore(initialState: MediaImportFeature.State(phase: .loading)) {
            MediaImportFeature()
        } withDependencies: {
            $0.mediaImport = MediaImportClient()
            $0.mediaImportStore = MediaImportStoreClient()
        }

        await store.send(.cached(loaded)) {
            $0.phase = .idle
        }
        await store.receive(\.delegate.imported, loaded)
    }

    @Test func cacheFailureSetsFailedAndDoesNotDelegate() async {
        struct CacheError: Error {}
        let errorDescription = CacheError().localizedDescription

        let store = TestStore(initialState: MediaImportFeature.State(phase: .loading)) {
            MediaImportFeature()
        } withDependencies: {
            $0.mediaImport = MediaImportClient()
            $0.mediaImportStore = MediaImportStoreClient(
                store: { _ in throw CacheError() },
                removeExpired: {}
            )
        }

        await store.send(.loaded([Self.payload("a.jpeg")]))
        await store.receive(\.failed) {
            $0.phase = .failed(errorDescription)
        }
    }

    @Test func cleanupFailureSetsFailedAndDoesNotStore() async {
        struct CleanupError: Error {}
        let errorDescription = CleanupError().localizedDescription
        let storedIDs = LockedBox<[String]>([])

        let store = TestStore(initialState: MediaImportFeature.State(phase: .loading)) {
            MediaImportFeature()
        } withDependencies: {
            $0.mediaImport = MediaImportClient()
            $0.mediaImportStore = MediaImportStoreClient(
                store: { payload in
                    storedIDs.mutate { $0.append(payload.metadata.id) }
                    return Self.media(from: payload)
                },
                removeExpired: { throw CleanupError() }
            )
        }

        await store.send(.loaded([Self.payload("a.jpeg")]))
        await store.receive(\.failed) {
            $0.phase = .failed(errorDescription)
        }

        #expect(storedIDs.value.isEmpty)
    }

    @Test func failedSetsFailedPhase() async {
        let store = TestStore(initialState: MediaImportFeature.State(phase: .loading)) {
            MediaImportFeature()
        } withDependencies: {
            $0.mediaImport = MediaImportClient()
            $0.mediaImportStore = MediaImportStoreClient()
        }

        await store.send(.failed("boom")) {
            $0.phase = .failed("boom")
        }
    }

    @Test func emptyPickedIsNoop() async {
        let store = TestStore(initialState: MediaImportFeature.State()) {
            MediaImportFeature()
        } withDependencies: {
            $0.mediaImport = MediaImportClient()
            $0.mediaImportStore = MediaImportStoreClient()
        }
        await store.send(.picked([]))
    }

    // MARK: - Helpers

    private nonisolated static func payload(_ id: String) -> MediaImportClient.Payload {
        MediaImportClient.Payload(
            metadata: MediaMetadata(
                id: id,
                name: id,
                contentType: "image/jpeg",
                kind: .image,
                size: nil
            ),
            data: Data([1, 2, 3])
        )
    }

    private nonisolated static func media(_ id: String) -> ImportedMedia {
        ImportedMedia(
            metadata: MediaMetadata(
                id: id,
                name: id,
                contentType: "image/jpeg",
                kind: .image,
                size: 1000
            ),
            fileURL: URL(fileURLWithPath: "/tmp/\(id)")
        )
    }

    private nonisolated static func media(from payload: MediaImportClient.Payload) -> ImportedMedia {
        ImportedMedia(
            metadata: payload.metadata.with(size: Int64(payload.data.count)),
            fileURL: URL(fileURLWithPath: "/tmp/\(payload.metadata.id)")
        )
    }
}
