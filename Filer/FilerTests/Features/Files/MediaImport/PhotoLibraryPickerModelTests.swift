import ComposableArchitecture
@testable import Filer
import Testing

@MainActor
struct PhotoLibraryPickerModelTests {
    private func makeSUT(_ phase: MediaImportFeature.State.Phase) -> PhotoLibraryPickerView.Model {
        let store = Store(initialState: MediaImportFeature.State(phase: phase)) { MediaImportFeature() }
        return PhotoLibraryPickerView.Model(store)
    }

    @Test func idlePhaseIsNotLoading() {
        #expect(makeSUT(.idle).isLoading == false)
    }

    @Test func loadingPhaseIsLoading() {
        #expect(makeSUT(.loading).isLoading == true)
    }

    @Test func failedPhaseIsNotLoading() {
        #expect(makeSUT(.failed("boom")).isLoading == false)
    }
}
