import ComposableArchitecture
@testable import Filer
import Testing

private struct Unimplemented: Error {}

@MainActor
struct PhotoLibraryPickerModelTests {
    @Test func idlePhaseIsNotLoading() {
        #expect(makeSUT(.idle).isLoading == false)
    }

    @Test func loadingPhaseIsLoading() {
        #expect(makeSUT(.loading).isLoading == true)
    }

    @Test func failedPhaseIsNotLoading() {
        #expect(makeSUT(.failed("boom")).isLoading == false)
    }

    // MARK: - Helpers

    private func makeSUT(_ phase: MediaImportFeature.State.Phase) -> PhotoLibraryPickerView.Model {
        let store = withDependencies {
            $0.mediaImport = Self.failingMediaImport()
            $0.mediaCache = Self.failingCache()
        } operation: {
            Store(initialState: MediaImportFeature.State(phase: phase)) {
                MediaImportFeature()
            }
        }
        return PhotoLibraryPickerView.Model(store)
    }

    private nonisolated static func failingMediaImport() -> MediaImportClient {
        MediaImportClient(load: { _ in throw MediaImportClient.Unimplemented() })
    }

    private nonisolated static func failingCache() -> MediaCacheClient {
        var cache = MediaCacheClient.testValue
        cache.store = { _ in throw Unimplemented() }
        cache.removeExpired = { throw Unimplemented() }
        return cache
    }
}
