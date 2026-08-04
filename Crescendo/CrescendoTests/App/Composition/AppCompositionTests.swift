import Testing

@testable import Crescendo

@MainActor
struct AppCompositionTests {
    @Test
    func storeStartsOnSearchWithAnEmptyIdleLibrary() {
        let store = AppComposition.makeStore()

        #expect(store.selectedTab == .search)
        #expect(store.library.library.items.isEmpty)
        #expect(store.library.loadStatus == .idle)
    }
}
