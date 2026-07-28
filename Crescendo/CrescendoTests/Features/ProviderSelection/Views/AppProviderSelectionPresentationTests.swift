import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppProviderSelectionPresentationTests {
    @Test
    func modelAcceptsAdapterProjectedProviderPresentation() {
        let model = ProviderSelectionView.Model(
            status: .disconnected,
            activeProviderName: "Active Provider",
            connectedProviderName: "Connected Provider",
            collapsedIcon: .generic,
            collapsedLabel: "Collapsed",
            accessibilityValue: "Accessible Provider Status",
            menuTitle: "Providers",
            providerRows: [],
            recoveryAction: nil,
            isSelectionEnabled: true
        )

        #expect(model.activeProviderName == "Active Provider")
        #expect(model.connectedProviderName == "Connected Provider")
        #expect(model.accessibilityValue == "Accessible Provider Status")
    }

    @Test(arguments: [
        (
            ProviderConnection.disconnected,
            ProviderSelectionView.Model.Status.disconnected,
            "Connect",
            ProviderSelectionView.Model.Icon.generic
        ),
        (
            .connecting(providerID: .testProvider, requestID: UUID(0)),
            .connecting(providerName: "Test Provider"),
            "Connecting to Test Provider…",
            .generic
        ),
        (
            .connected(
                providerID: .testProvider,
                access: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            .connected(providerName: "Test Provider"),
            "Test Provider",
            .generic
        ),
        (
            .denied(providerID: .testProvider),
            .needsAccess(providerName: "Test Provider"),
            "Test Provider · Needs Access",
            .generic
        ),
        (
            .restricted(providerID: .testProvider),
            .restricted(providerName: "Test Provider"),
            "Test Provider · Restricted",
            .generic
        ),
        (
            .failed(providerID: .testProvider),
            .failed(providerName: "Test Provider"),
            "Test Provider · Connection Failed",
            .generic
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
                    providerID: .testProvider,
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
    func jamendoUsesGenericProviderArtwork() {
        let connection = ProviderConnection.connected(
            providerID: .jamendo,
            access: MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .eligible
            )
        )
        let model = ProviderSelectionView.Model(
            makeStore(
                connection: connection,
                providers: [.jamendo]
            )
        )

        #expect(model.collapsedIcon == .generic)
        #expect(model.providerRows.map(\.icon) == [.generic])
    }

    @Test
    func playbackOperationDisablesProviderSelection() {
        let song = Track(
            id: .init(providerID: .testProvider, nativeID: "selected"),
            title: "Selected",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
        let tracks = IdentifiedArray(uniqueElements: [song])
        let model = ProviderSelectionView.Model(
            makeStore(
                connection: connectedConnection,
                pendingPlaybackTransition: PendingPlaybackTransition(
                    requestID: UUID(0),
                    queue: tracks,
                    targetTrackID: song.id
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
            makeStore(connection: .failed(providerID: .testProvider), actions: actions)
        )
        #expect(failed.recoveryAction?.label == "Try Again")
        failed.recoveryAction?.perform()

        let needsAccess = ProviderSelectionView.Model(
            makeStore(connection: .denied(providerID: .testProvider), actions: actions)
        )
        #expect(needsAccess.recoveryAction?.label == "Open Settings")
        needsAccess.recoveryAction?.perform()

        #expect(
            actions.value == [
                .providerSelected(.testProvider),
                .providerConnection(.retryButtonTapped),
                .providerConnection(.openSettingsButtonTapped),
            ]
        )
    }

    // MARK: - Helpers

    private var connectedConnection: ProviderConnection {
        .connected(
            providerID: .testProvider,
            access: MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .eligible
            )
        )
    }

    private func makeStore(
        connection: ProviderConnection,
        providers: [ProviderDescriptor] = [.testProvider],
        pendingPlaybackTransition: PendingPlaybackTransition? = nil,
        actions: LockIsolated<[AppFeature.Action]>? = nil
    ) -> StoreOf<AppFeature> {
        Store(
            initialState: AppFeature.State(
                providerConnection: ProviderConnectionFeature.State(
                    providers: providers,
                    connection: connection
                ),
                search: SearchFeature.State(
                    query: "",
                    status: .idle,
                    providerAccess: nil,
                    providerID: .testProvider
                ),
                playback: PlaybackFeature.State(
                    providerID: connection.providerID,
                    queue: PlaybackQueueFeature.State(
                        tracks: [],
                        playbackOrder: PlaybackQueueOrder(trackIDs: []),
                        currentTrackID: nil,
                        repeatMode: .off,
                        shuffleMode: .off
                    ),
                    status: .idle,
                    failureNotice: nil,
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: PlaybackTimelineFeature.State(
                        confirmedPosition: 0,
                        duration: nil,
                        isSeekable: false,
                        interaction: .idle
                    ),
                    pendingPlaybackTransition: pendingPlaybackTransition,
                    pendingStatusChange: nil,
                    pendingProviderReset: nil,
                    isPlayerPresented: false
                ),
                providerSwitch: nil
            )
        ) {
            Reduce { _, action in
                actions?.withValue { $0.append(action) }
                return .none
            }
        }
    }
}
