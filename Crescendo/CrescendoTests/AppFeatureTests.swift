import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppFeatureTests {
    @Test
    func taskLeavesSoleProviderDisconnected() async {
        let store = makeStore()

        await store.send(.task)

        #expect(store.state.providerConnection.connection == .disconnected)
        #expect(store.state.requiresProviderSelection)
    }

    @Test
    func providerSelectionRoutesConnectionThroughChild() async {
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let store = makeStore(currentAccess: { access })

        await store.send(.providerSelected(.appleMusic))
        await store.receive(.providerConnection(.connect(.appleMusic)))
        await store.receive(
            .providerConnection(.startConnection(.appleMusic))
        ) {
            $0.providerConnection.connection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: .appleMusic,
                        providerChanged: true
                    )
                )
            )
        )
        await store.receive(.resetProviderOwnedState(.appleMusic))
        await store.receive(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(0),
                    providerID: .appleMusic,
                    access: access
                )
            )
        )
        await store.receive(
            .providerConnection(
                .accessResolved(
                    requestID: UUID(0),
                    providerID: .appleMusic,
                    access: access
                )
            )
        ) {
            $0.providerConnection.connection = .connected(
                providerID: .appleMusic,
                access: access
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(
                            providerID: .appleMusic,
                            access: access
                        )
                    )
                )
            )
        ) {
            $0.search.playbackEligibility = .eligible
        }
    }

    @Test
    func changedProviderConnectionStartResetsProviderOwnedState() async {
        let song = makeSong()
        let futureProvider = makeProvider(id: "future")
        let state = makeState(
            providers: [.appleMusic, futureProvider],
            connection: .connecting(
                providerID: futureProvider.id,
                requestID: UUID(0)
            ),
            search: SearchFeature.State(
                query: "Selected song",
                phase: .loaded([song]),
                playbackEligibility: .eligible
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: song,
                phase: .observing(
                    MusicPlaybackSnapshot(
                        currentItem: song,
                        status: .playing,
                        currentTime: 42
                    )
                ),
                playbackEligibility: .eligible,
                capabilities: .allEnabled
            ),
            isPlayerPresented: true
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: futureProvider.id,
                        providerChanged: true
                    )
                )
            )
        )
        await store.receive(.resetProviderOwnedState(futureProvider.id)) {
            $0.search = SearchFeature.State(
                query: "",
                phase: .idle,
                playbackEligibility: .unknown
            )
            $0.musicPlayback = MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: futureProvider.musicCapabilities
            )
            $0.isPlayerPresented = false
        }
    }

    @Test
    func unchangedProviderConnectionStartPreservesProviderOwnedState() async {
        let state = makeState(
            connection: .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: .appleMusic,
                        providerChanged: false
                    )
                )
            )
        )

        #expect(store.state == state)
    }

    @Test
    func resolvedConnectionSynchronizesPlaybackEligibility() async {
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .ineligible
        )
        let state = makeState(
            connection: .connected(
                providerID: .appleMusic,
                access: access
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(
                            providerID: .appleMusic,
                            access: access
                        )
                    )
                )
            )
        ) {
            $0.search.playbackEligibility = .ineligible
        }
    }

    @Test
    func unavailableProviderCannotBeSelected() async {
        let state = makeState(providers: [])
        let store = makeStore(state: state)

        await store.send(.providerSelected("missing"))

        #expect(store.state == state)
    }

    // MARK: - Helpers

    private func makeStore(
        state: AppFeature.State? = nil,
        currentAccess: @escaping @Sendable () async -> MusicProviderAccess = {
            MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .unknown
            )
        }
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state ?? makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = currentAccess
        }
    }

    private func makeState(
        providers: [ProviderDescriptor] = [.appleMusic],
        connection: ProviderConnection = .disconnected,
        search: SearchFeature.State? = nil,
        musicPlayback: MusicPlaybackFeature.State? = nil,
        isPlayerPresented: Bool = false
    ) -> AppFeature.State {
        AppFeature.State(
            providerConnection: ProviderConnectionFeature.State(
                providers: providers,
                connection: connection
            ),
            search: search
                ?? SearchFeature.State(
                    query: "",
                    phase: .idle,
                    playbackEligibility: .unknown
                ),
            musicPlayback: musicPlayback
                ?? MusicPlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled
                ),
            isPlayerPresented: isPlayerPresented,
            pendingProviderID: nil,
            providerSwitchRequestID: nil,
            playbackTransition: nil
        )
    }

    private func makeProvider(id: ProviderID) -> ProviderDescriptor {
        ProviderDescriptor(
            id: id,
            name: "Future",
            musicCapabilities: MusicProviderCapabilities(
                supportsCatalogSearch: true,
                supportsEmbeddedPlayback: true,
                supportsSeeking: false,
                supportsQueueReplacement: true
            )
        )
    }

    private func makeAccess(
        authorization: MusicAuthorizationStatus,
        playbackEligibility: CatalogPlaybackEligibility = .unknown
    ) -> MusicProviderAccess {
        MusicProviderAccess(
            authorization: authorization,
            playbackEligibility: playbackEligibility
        )
    }

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: .appleMusic, nativeID: "selected"),
            title: "Selected song",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
