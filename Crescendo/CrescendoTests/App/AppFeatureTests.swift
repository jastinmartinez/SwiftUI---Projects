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
        await store.receive(.musicPlayback(.timeline(.reset)))
        await store.receive(.replaceProviderOwnedState(.appleMusic))
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
            $0.search.providerAccess = access
        }
    }

    @Test
    func changedProviderConnectionStartResetsProviderOwnedState() async {
        let suspendedSeek = SuspendedSeekProbe()
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
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
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
                capabilities: .allEnabled,
                timeline: MusicPlaybackTimelineFeature.State(
                    interaction: .idle
                )
            ),
            isPlayerPresented: true
        )
        let store = makeStore(
            state: state,
            seek: suspendedSeek.callAsFunction
        )
        await startSuspendedSeek(suspendedSeek, on: store)

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
        await store.receive(.resetProviderOwnedState(futureProvider.id))
        await store.receive(.musicPlayback(.timeline(.reset))) {
            $0.musicPlayback.timeline.interaction = .idle
        }
        #expect(suspendedSeek.cancellationObserved.value)
        #expect(store.state.musicPlayback.selectedSong == song)

        await store.receive(.replaceProviderOwnedState(futureProvider.id)) {
            $0.search = SearchFeature.State(
                query: "",
                phase: .idle,
                providerAccess: nil
            )
            $0.musicPlayback = MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: futureProvider.musicCapabilities,
                timeline: MusicPlaybackTimelineFeature.State(
                    interaction: .idle
                )
            )
            $0.isPlayerPresented = false
        }

        suspendedSeek.fail(with: .network)
        await store.finish()
        #expect(store.state.musicPlayback.timeline.interaction == .idle)
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
    func resolvedConnectionSynchronizesProviderAccess() async {
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
            $0.search.providerAccess = access
        }
    }

    @Test(arguments: [
        ProviderConnection.disconnected,
        .denied(providerID: .appleMusic),
        .restricted(providerID: .appleMusic),
        .failed(providerID: .appleMusic),
    ])
    func unavailableConnectionClearsProviderAccess(
        connection: ProviderConnection
    ) async {
        let staleAccess = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let state = makeState(
            connection: connection,
            search: SearchFeature.State(
                query: "result",
                phase: .loaded([makeSong()]),
                providerAccess: staleAccess
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(.connectionResolved(connection))
            )
        ) {
            $0.search.providerAccess = nil
        }
    }

    @Test
    func selectedSongUsesConnectionPlaybackEligibility() async {
        let song = makeSong()
        let previousSong = makeSong(nativeID: "previous")
        let connectionAccess = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let state = makeState(
            connection: .connected(
                providerID: .appleMusic,
                access: connectionAccess
            ),
            search: SearchFeature.State(
                query: "Selected song",
                phase: .loaded([song]),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .ineligible
                )
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: previousSong,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: .allEnabled,
                timeline: MusicPlaybackTimelineFeature.State(
                    interaction: .dragging(position: 18)
                )
            )
        )
        let store = makeStore(state: state)

        await store.send(.search(.delegate(.songSelected(song)))) {
            $0.isPlayerPresented = true
        }
        await store.receive(
            .musicPlayback(
                .songSelected(song, playbackEligibility: .eligible)
            )
        )
        await store.receive(.musicPlayback(.timeline(.reset))) {
            $0.musicPlayback.timeline.interaction = .idle
        }
        await store.receive(
            .musicPlayback(
                .applySongSelection(
                    song,
                    playbackEligibility: .eligible
                )
            )
        ) {
            $0.musicPlayback.selectedSong = song
            $0.musicPlayback.playbackEligibility = .eligible
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
        },
        seek: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state ?? makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.currentAccess = currentAccess
            $0.musicProvider.seek = seek
        }
    }

    private func startSuspendedSeek(
        _ suspendedSeek: SuspendedSeekProbe,
        on store: TestStoreOf<AppFeature>
    ) async {
        await store.send(
            .musicPlayback(.timeline(.positionChanged(18)))
        ) {
            $0.musicPlayback.timeline.interaction = .dragging(position: 18)
        }
        await store.send(.musicPlayback(.timeline(.dragEnded))) {
            $0.musicPlayback.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 18
            )
        }
        await suspendedSeek.waitUntilStarted()
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
                    providerAccess: nil
                ),
            musicPlayback: musicPlayback
                ?? MusicPlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: MusicPlaybackTimelineFeature.State(
                        interaction: .idle
                    )
                ),
            isPlayerPresented: isPlayerPresented,
            providerSwitch: nil,
            playbackCommand: nil
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

    private func makeSong(nativeID: String = "selected") -> SongSummary {
        SongSummary(
            id: .init(providerID: .appleMusic, nativeID: nativeID),
            title: "Selected song",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
