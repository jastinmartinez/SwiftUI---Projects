import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AppProviderSelectionPresentationTests {
    @Test
    func providerSelectionMapsStateAndForwardsSelection() {
        let actions = LockIsolated<[AppFeature.Action]>([])
        let store = Store<AppFeature.State, AppFeature.Action>(
            initialState: makeState()
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
        let model = ProviderSelectionView.Model(store)

        #expect(model.providers == [.appleMusic])
        #expect(model.activeProviderID == MusicProviderID.appleMusic)
        #expect(model.activeProviderName == "Apple Music")
        #expect(model.isSelectionEnabled)

        model.onSelect(.appleMusic)

        #expect(actions.value == [.providerSelected(.appleMusic)])
    }

    // MARK: - Helpers

    private func makeState() -> AppFeature.State {
        AppFeature.State(
            registeredProviders: [.appleMusic],
            activeProviderID: MusicProviderDescriptor.appleMusic.id,
            search: SearchFeature.State(
                query: "",
                phase: .idle,
                playbackEligibility: .unknown
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: .allEnabled
            ),
            isPlayerPresented: false,
            pendingProviderID: nil,
            providerSwitchRequestID: nil,
            playbackTransition: nil
        )
    }
}
