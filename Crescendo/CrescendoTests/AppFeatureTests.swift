import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppFeatureTests {
    @Test
    func appStartsAndAutoSelectsSoleProvider() async {
        let store = makeStore(
            registeredProviders: [.appleMusic],
            activeProviderID: nil
        )

        await store.send(.task) {
            $0.activeProviderID = "apple-music"
        }
        #expect(!store.state.requiresProviderSelection)
    }

    @Test
    func multipleProvidersRequireSelection() async {
        let events = LockIsolated<[String]>([])
        let store = makeStore(
            registeredProviders: [
                .appleMusic,
                makeProvider(id: "future"),
            ],
            activeProviderID: nil,
            pause: {
                events.withValue { $0.append("pause") }
            }
        )

        await store.send(.task)
        #expect(store.state.requiresProviderSelection)

        await store.send(.providerSelected("future")) {
            $0.activeProviderID = "future"
        }
        #expect(!store.state.requiresProviderSelection)
        #expect(events.value.isEmpty)
    }

    @Test
    func unavailableProviderCannotBeSelected() async {
        let store = makeStore(
            registeredProviders: [],
            activeProviderID: nil
        )

        await store.send(.providerSelected("missing"))
        #expect(store.state.activeProviderID == nil)
    }

    // MARK: - Helpers

    private func makeStore(
        registeredProviders: [MusicProviderDescriptor],
        activeProviderID: MusicProviderID?,
        pause: @escaping @Sendable () async throws -> Void = {}
    ) -> TestStoreOf<AppFeature> {
        TestStore(
            initialState: AppFeature.State(
                registeredProviders: registeredProviders,
                activeProviderID: activeProviderID,
                search: makeSearchState(),
                musicPlayback: makeMusicPlaybackState(),
                isPlayerPresented: false,
                pendingProviderID: nil,
                providerSwitchRequestID: nil,
                playbackTransition: nil
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.pause = pause
        }
    }

    private func makeProvider(id: MusicProviderID) -> MusicProviderDescriptor {
        MusicProviderDescriptor(
            id: id,
            capabilities: .init(
                supportsCatalogSearch: true,
                supportsEmbeddedPlayback: true,
                supportsSeeking: true,
                supportsQueueReplacement: true
            )
        )
    }

    private func makeSearchState() -> SearchFeature.State {
        SearchFeature.State(
            query: "",
            phase: .idle,
            playbackEligibility: .unknown
        )
    }

    private func makeMusicPlaybackState() -> MusicPlaybackFeature.State {
        MusicPlaybackFeature.State(
            selectedSong: nil,
            phase: .observing(.idle),
            playbackEligibility: .unknown,
            capabilities: .allEnabled
        )
    }
}
