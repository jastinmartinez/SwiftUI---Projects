import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AppFeatureTests {
    private let capabilities = MusicProviderCapabilities(
        supportsCatalogSearch: true,
        supportsEmbeddedPlayback: true,
        supportsSeeking: true,
        supportsQueueReplacement: true
    )

    @Test
    func appStartsAndAutoSelectsSoleProvider() async {
        let store = TestStore(
            initialState: AppFeature.State(
                registeredProviders: [.appleMusic],
                activeProviderID: nil
            )
        ) {
            AppFeature()
        }

        await store.send(.task) {
            $0.activeProviderID = "apple-music"
        }
        #expect(!store.state.requiresProviderSelection)
    }

    @Test
    func multipleProvidersRequireSelection() async {
        let store = TestStore(
            initialState: AppFeature.State(
                registeredProviders: [
                    .appleMusic,
                    .init(id: "future", capabilities: capabilities),
                ],
                activeProviderID: nil
            )
        ) {
            AppFeature()
        }

        await store.send(.task)
        #expect(store.state.requiresProviderSelection)

        await store.send(.providerSelected("future")) {
            $0.activeProviderID = "future"
        }
        #expect(!store.state.requiresProviderSelection)
    }

    @Test
    func unavailableProviderCannotBeSelected() async {
        let store = TestStore(
            initialState: AppFeature.State(
                registeredProviders: [],
                activeProviderID: nil
            )
        ) {
            AppFeature()
        }

        await store.send(.providerSelected("missing"))
        #expect(store.state.activeProviderID == nil)
    }
}
