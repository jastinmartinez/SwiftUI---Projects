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
        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let store = makeStore {
            $0.providerAccess.currentAccess = { access }
        }

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
        await store.receive(.search(.cancelSearch))
        await store.receive(.playback(.cancelPendingOperation))
        await store.receive(.playback(.timeline(.reset)))
        await store.receive(.replaceProviderOwnedState(.appleMusic)) {
            $0.playback.providerID = .appleMusic
        }
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
    func changedProviderConnectionResetsProviderOwnedState() async {
        let song = makeSong()
        let queue = IdentifiedArray(uniqueElements: [song])
        let futureProvider = makeProvider(id: "future")
        let state = makeState(
            providers: [.appleMusic, futureProvider],
            connection: .connecting(
                providerID: futureProvider.id,
                requestID: UUID(0)
            ),
            search: SearchFeature.State(
                query: song.title,
                status: .loaded(
                    SearchPaginationFeature.State(
                        songs: queue,
                        nextCursor: nil,
                        status: .idle
                    )
                ),
                providerAccess: .init(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            playback: PlaybackFeature.State(
                providerID: .appleMusic,
                queue: .init(songs: queue, currentItemID: song.id),
                status: .playing,
                failure: .network,
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: .init(
                    confirmedPosition: 42,
                    interaction: .dragging(position: 50)
                ),
                pendingOperation: nil
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
        await store.receive(.resetProviderOwnedState(futureProvider.id))
        await store.receive(.search(.cancelSearch)) {
            $0.search.status = .idle
        }
        await store.receive(.playback(.cancelPendingOperation))
        await store.receive(.playback(.timeline(.reset))) {
            $0.playback.timeline.confirmedPosition = 0
            $0.playback.timeline.interaction = .idle
        }
        await store.receive(.replaceProviderOwnedState(futureProvider.id)) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: nil
            )
            $0.playback = PlaybackFeature.State(
                providerID: futureProvider.id,
                queue: .init(songs: [], currentItemID: nil),
                status: .idle,
                failure: nil,
                playbackEligibility: .unknown,
                capabilities: futureProvider.musicCapabilities,
                timeline: .init(
                    confirmedPosition: 0,
                    interaction: .idle
                ),
                pendingOperation: nil
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
    func unavailableConnectionClearsProviderAccess() async {
        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let state = makeState(
            search: SearchFeature.State(
                query: "Song",
                status: .idle,
                providerAccess: access
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(.connectionResolved(.disconnected))
            )
        ) {
            $0.search.providerAccess = nil
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
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state ?? makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            configureDependencies(&$0)
        }
    }

    private func makeState(
        providers: [ProviderDescriptor] = [.appleMusic],
        connection: ProviderConnection = .disconnected,
        search: SearchFeature.State? = nil,
        playback: PlaybackFeature.State? = nil,
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
                    status: .idle,
                    providerAccess: nil
                ),
            playback: playback
                ?? PlaybackFeature.State(
                    providerID: nil,
                    queue: .init(songs: [], currentItemID: nil),
                    status: .idle,
                    failure: nil,
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: .init(
                        confirmedPosition: 0,
                        interaction: .idle
                    ),
                    pendingOperation: nil
                ),
            isPlayerPresented: isPlayerPresented,
            providerSwitch: nil
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

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: .appleMusic, nativeID: "selected"),
            title: "Selected song",
            artistName: "Artist",
            artworkURL: nil,
            duration: 180
        )
    }
}
