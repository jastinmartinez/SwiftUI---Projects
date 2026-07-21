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
            "Connect",
            ProviderSelectionView.Model.Icon.generic
        ),
        (
            .connecting(providerID: .appleMusic, requestID: UUID(0)),
            .connecting(providerName: "Apple Music"),
            "Connecting to Apple Music…",
            .appleMusic
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
            "Apple Music",
            .appleMusic
        ),
        (
            .denied(providerID: .appleMusic),
            .needsAccess(providerName: "Apple Music"),
            "Apple Music · Needs Access",
            .appleMusic
        ),
        (
            .restricted(providerID: .appleMusic),
            .restricted(providerName: "Apple Music"),
            "Apple Music · Restricted",
            .appleMusic
        ),
        (
            .failed(providerID: .appleMusic),
            .failed(providerName: "Apple Music"),
            "Apple Music · Connection Failed",
            .appleMusic
        ),
    ])
    func providerSelectionPresentsEachConnectionStatus(
        connection: ProviderConnection,
        expectedStatus: ProviderSelectionView.Model.Status,
        expectedCollapsedLabel: String,
        expectedCollapsedIcon: ProviderSelectionView.Model.Icon
    ) {
        let model = ProviderSelectionView.Model(makeStore(connection: connection))

        #expect(model.status == expectedStatus)
        #expect(model.collapsedLabel == expectedCollapsedLabel)
        #expect(model.collapsedIcon == expectedCollapsedIcon)
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

    @Test(arguments: [
        PlaybackCommandFeature.Command.play(
            itemIDs: [
                MusicItemID(providerID: .appleMusic, nativeID: "selected")
            ],
            startingItemID: MusicItemID(
                providerID: .appleMusic,
                nativeID: "selected"
            )
        ),
        .resume(
            MusicItemID(providerID: .appleMusic, nativeID: "selected")
        ),
    ])
    func playbackCommandDisablesProviderSelection(
        command: PlaybackCommandFeature.Command
    ) {
        let model = ProviderSelectionView.Model(
            makeStore(
                connection: connectedConnection,
                playbackCommand: PlaybackCommandFeature.State(
                    command: command,
                    requestID: UUID(0)
                )
            )
        )

        #expect(!model.isSelectionEnabled)
        #expect(!model.providerRows[0].isEnabled)
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
        playbackCommand: PlaybackCommandFeature.State? = nil,
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
                    status: .idle,
                    providerAccess: nil
                ),
                playback: PlaybackFeature.State(
                    selectedSong: nil,
                    queue: PlaybackQueueFeature.State(
                        songs: [],
                        currentItemID: nil
                    ),
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: PlaybackTimelineFeature.State(
                        interaction: .idle
                    )
                ),
                isPlayerPresented: false,
                providerSwitch: nil,
                playbackCommand: playbackCommand
            )
        ) {
            Reduce { _, action in
                actions?.withValue { $0.append(action) }
                return .none
            }
        }
    }
}
