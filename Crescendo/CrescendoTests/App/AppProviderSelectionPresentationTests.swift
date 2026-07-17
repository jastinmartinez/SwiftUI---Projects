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
        #expect(model.activeProviderID == ProviderID.appleMusic)
        #expect(model.activeProviderName == "Apple Music")
        #expect(model.isSelectionEnabled)

        model.onSelect(.appleMusic)

        #expect(actions.value == [.providerSelected(.appleMusic)])
    }

    @Test
    func providerAccessibilityValueAnnouncesActiveProvider() {
        let model = ProviderSelectionView.Model(
            providers: [.appleMusic],
            activeProviderID: .appleMusic,
            isSelectionEnabled: true,
            onSelect: { _ in }
        )

        #expect(model.accessibilityValue == "Apple Music")
    }

    @Test
    func providerAccessibilityValueAnnouncesMissingProvider() {
        let model = ProviderSelectionView.Model(
            providers: [],
            activeProviderID: nil,
            isSelectionEnabled: true,
            onSelect: { _ in }
        )

        #expect(
            model.accessibilityValue == Locs.ProviderSelection.noActiveProvider
        )
        #expect(model.accessibilityValue == "No provider selected")
    }

    // MARK: - Helpers

    private func makeState() -> AppFeature.State {
        AppFeature.State(
            registeredProviders: [.appleMusic],
            providerConnection: .connected(
                providerID: .appleMusic,
                access: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .unknown
                )
            ),
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
