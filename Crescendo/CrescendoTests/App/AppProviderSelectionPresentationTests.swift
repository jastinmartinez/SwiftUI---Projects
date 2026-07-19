import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppProviderSelectionPresentationTests {
    @Test(arguments: [
        (
            ProviderConnection.disconnected,
            ProviderSelectionView.Model.Status.disconnected,
            "Connect"
        ),
        (
            .connecting(providerID: .appleMusic, requestID: UUID(0)),
            .connecting(providerName: "Apple Music"),
            "Connecting to Apple Music…"
        ),
        (
            .connected(
                providerID: .appleMusic,
                access: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            .connected(providerName: "Apple Music"),
            "Apple Music"
        ),
        (
            .denied(providerID: .appleMusic),
            .needsAccess(providerName: "Apple Music"),
            "Apple Music · Needs Access"
        ),
        (
            .restricted(providerID: .appleMusic),
            .restricted(providerName: "Apple Music"),
            "Apple Music · Restricted"
        ),
        (
            .failed(providerID: .appleMusic),
            .failed(providerName: "Apple Music"),
            "Apple Music · Connection Failed"
        ),
    ])
    func providerSelectionPresentsEachConnectionStatus(
        connection: ProviderConnection,
        expectedStatus: ProviderSelectionView.Model.Status,
        expectedCollapsedLabel: String
    ) {
        let model = ProviderSelectionView.Model(makeStore(connection: connection))

        #expect(model.status == expectedStatus)
        #expect(model.collapsedLabel == expectedCollapsedLabel)
    }

    @Test
    func connectingDisablesRepeatSelection() {
        let model = ProviderSelectionView.Model(
            makeStore(
                connection: .connecting(
                    providerID: .appleMusic,
                    requestID: UUID(0)
                )
            )
        )

        #expect(!model.isSelectionEnabled)
        #expect(!model.providerRows[0].isEnabled)
    }

    @Test
    func connectedProviderRowIsSelected() {
        let model = ProviderSelectionView.Model(
            makeStore(connection: connectedConnection)
        )

        #expect(model.providerRows[0].isSelected)
    }

    @Test
    func providerAndRecoveryActionsForwardToTheReducer() {
        let actions = LockIsolated<[AppFeature.Action]>([])
        let store = makeStore(
            connection: .disconnected,
            actions: actions
        )

        let disconnected = ProviderSelectionView.Model(store)
        disconnected.providerRows[0].onSelect()

        let failed = ProviderSelectionView.Model(
            makeStore(connection: .failed(providerID: .appleMusic), actions: actions)
        )
        #expect(failed.recoveryAction?.label == "Try Again")
        failed.recoveryAction?.perform()

        let needsAccess = ProviderSelectionView.Model(
            makeStore(connection: .denied(providerID: .appleMusic), actions: actions)
        )
        #expect(needsAccess.recoveryAction?.label == "Open Settings")
        needsAccess.recoveryAction?.perform()

        #expect(
            actions.value == [
                .providerSelected(.appleMusic),
                .providerConnection(.retryButtonTapped),
                .providerConnection(.openSettingsButtonTapped),
            ]
        )
    }

    // MARK: - Helpers

    private var connectedConnection: ProviderConnection {
        .connected(
            providerID: .appleMusic,
            access: MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .eligible
            )
        )
    }

    private func makeStore(
        connection: ProviderConnection,
        actions: LockIsolated<[AppFeature.Action]>? = nil
    ) -> StoreOf<AppFeature> {
        Store(
            initialState: AppFeature.State(
                providerConnection: ProviderConnectionFeature.State(
                    providers: [.appleMusic],
                    connection: connection
                ),
                search: SearchFeature.State(
                    query: "",
                    phase: .idle,
                    providerAccess: nil
                ),
                musicPlayback: MusicPlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled
                ),
                isPlayerPresented: false,
                providerSwitch: nil,
                playbackStart: nil
            )
        ) {
            Reduce { _, action in
                actions?.withValue { $0.append(action) }
                return .none
            }
        }
    }
}
