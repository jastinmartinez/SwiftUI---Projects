import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppProviderSwitchingTests {
    @Test
    func connectedSelectionCreatesProviderSwitch() async {
        let store = makeStore()

        await store.send(.providerSelected("future")) {
            $0.providerSwitch = ProviderSwitchFeature.State(
                sourceProviderID: .appleMusic,
                phase: .ready(targetProviderID: "future")
            )
        }
        await store.receive(.providerSwitch(.start))
        await store.receive(
            .providerSwitch(
                .beginPause(targetProviderID: "future", requestID: UUID(0))
            )
        ) {
            $0.providerSwitch?.phase = .pausing(
                targetProviderID: "future",
                requestID: UUID(0)
            )
        }
        await store.send(.providerSelected(.appleMusic))
        await store.receive(.providerSwitch(.cancel))
        await store.receive(.providerSwitch(.delegate(.cancelled))) {
            $0.providerSwitch = nil
        }
    }

    @Test
    func reselectingActiveProviderRoutesCancellation() async {
        let store = makeStore(
            state: makeState(
                providerSwitch: ProviderSwitchFeature.State(
                    sourceProviderID: .appleMusic,
                    phase: .pausing(
                        targetProviderID: "future",
                        requestID: UUID(0)
                    )
                )
            )
        )

        await store.send(.providerSelected(.appleMusic))
        await store.receive(.providerSwitch(.cancel))
        await store.receive(.providerSwitch(.delegate(.cancelled))) {
            $0.providerSwitch = nil
        }
    }

    @Test
    func newerSelectionRoutesReplacement() async {
        let store = makeStore(
            state: makeState(
                providerSwitch: ProviderSwitchFeature.State(
                    sourceProviderID: .appleMusic,
                    phase: .pausing(
                        targetProviderID: "future",
                        requestID: UUID(0)
                    )
                )
            )
        )

        await store.send(.providerSelected("third"))
        await store.receive(.providerSwitch(.targetChanged("third")))
        await store.receive(
            .providerSwitch(
                .beginPause(targetProviderID: "third", requestID: UUID(0))
            )
        ) {
            $0.providerSwitch?.phase = .pausing(
                targetProviderID: "third",
                requestID: UUID(0)
            )
        }
        await store.send(.providerSelected(.appleMusic))
        await store.receive(.providerSwitch(.cancel))
        await store.receive(.providerSwitch(.delegate(.cancelled))) {
            $0.providerSwitch = nil
        }
    }

    @Test
    func readyToConnectRoutesIntoProviderConnection() async {
        let store = makeStore(
            state: makeState(
                providerSwitch: ProviderSwitchFeature.State(
                    sourceProviderID: .appleMusic,
                    phase: .pausing(
                        targetProviderID: "future",
                        requestID: UUID(0)
                    )
                )
            )
        )

        await store.send(.providerSwitch(.delegate(.readyToConnect("future")))) {
            $0.providerSwitch = nil
        }
        await store.receive(.providerConnection(.connect("future")))
        await store.receive(.providerConnection(.startConnection("future"))) {
            $0.providerConnection.connection = .connecting(
                providerID: "future",
                requestID: UUID(0)
            )
            $0.search.providerAccess = nil
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: "future",
                        providerChanged: true
                    )
                )
            )
        )
        await store.receive(.resetProviderOwnedState("future"))
        await store.receive(.search(.cancelSearch)) {
            $0.search.status = .idle
        }
        await store.receive(.playback(.cancelPendingOperation))
        await store.receive(.playback(.timeline(.reset))) {
            $0.playback.timeline.confirmedPosition = 0
        }
        await store.receive(.replaceProviderOwnedState("future")) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: nil
            )
            $0.playback = PlaybackFeature.State(
                providerID: "future",
                queue: PlaybackQueueFeature.State(
                    songs: [],
                    currentItemID: nil
                ),
                status: .idle,
                failure: nil,
                playbackEligibility: .unknown,
                capabilities: futureCapabilities,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: 0,
                    interaction: .idle
                ),
                pendingOperation: nil
            )
            $0.isPlayerPresented = false
        }
        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        await store.receive(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(0),
                    providerID: "future",
                    access: access
                )
            )
        )
        await store.receive(
            .providerConnection(
                .accessResolved(
                    requestID: UUID(0),
                    providerID: "future",
                    access: access
                )
            )
        ) {
            $0.providerConnection.connection = .connected(
                providerID: "future",
                access: access
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(providerID: "future", access: access)
                    )
                )
            )
        ) {
            $0.search.providerAccess = access
        }
    }

    @Test
    func failedSwitchPreservesProviderOwnedState() async {
        let state = makeState(
            providerSwitch: ProviderSwitchFeature.State(
                sourceProviderID: .appleMusic,
                phase: .pausing(
                    targetProviderID: "future",
                    requestID: UUID(0)
                )
            )
        )
        let store = makeStore(state: state)

        await store.send(.providerSwitch(.delegate(.failed))) {
            $0.providerSwitch = nil
        }

        #expect(store.state.search == state.search)
        #expect(store.state.playback == state.playback)
        #expect(store.state.isPlayerPresented == state.isPlayerPresented)
        #expect(store.state.providerConnection == state.providerConnection)
    }

    @Test
    func providerSelectionIsRejectedDuringPlaybackOperation() async {
        let song = makeSong()
        let songs = IdentifiedArray(uniqueElements: [song])
        let state = makeState(
            pendingOperation: .queueReplacement(
                PlaybackFeature.PendingQueueReplacement(
                    requestID: UUID(0),
                    songs: songs,
                    startingItemID: song.id
                )
            )
        )
        let store = makeStore(state: state)

        await store.send(.providerSelected("future"))

        #expect(store.state == state)
    }

    @Test
    func searchResultTapIsRejectedDuringProviderSwitch() async {
        let song = makeSong(nativeID: "next")
        let state = makeState(
            providerSwitch: ProviderSwitchFeature.State(
                sourceProviderID: .appleMusic,
                phase: .pausing(
                    targetProviderID: "future",
                    requestID: UUID(0)
                )
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .search(
                .delegate(
                    .songTapped(
                        song,
                        loadedResults: IdentifiedArray(uniqueElements: [song])
                    )
                )
            )
        )

        #expect(store.state == state)
    }

    // MARK: - Helpers

    private var futureCapabilities: MusicProviderCapabilities {
        MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: false,
            supportsQueueReplacement: true
        )
    }

    private func makeStore(
        state: AppFeature.State? = nil
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state ?? makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackControl.pause = { try await Task.sleep(for: .seconds(60)) }
            $0.providerAccess.currentAccess = {
                return MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            }
        }
    }

    private func makeState(
        providerSwitch: ProviderSwitchFeature.State? = nil,
        pendingOperation: PlaybackFeature.PendingOperation? = nil
    ) -> AppFeature.State {
        let song = makeSong()
        let queue = IdentifiedArray(uniqueElements: [song])
        return AppFeature.State(
            providerConnection: ProviderConnectionFeature.State(
                providers: [
                    .appleMusic,
                    makeProvider(
                        id: "future",
                        musicCapabilities: futureCapabilities
                    ),
                    makeProvider(id: "third", musicCapabilities: .allEnabled),
                ],
                connection: .connected(
                    providerID: .appleMusic,
                    access: MusicProviderAccess(
                        authorization: .authorized,
                        playbackEligibility: .eligible
                    )
                )
            ),
            search: SearchFeature.State(
                query: "Selected song",
                status: .loaded(
                    SearchPaginationFeature.State(
                        songs: [makeSong()],
                        nextCursor: nil,
                        status: .idle
                    )
                ),
                providerAccess: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            playback: PlaybackFeature.State(
                providerID: .appleMusic,
                queue: PlaybackQueueFeature.State(
                    songs: queue,
                    currentItemID: song.id
                ),
                status: .playing,
                failure: nil,
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: 42,
                    interaction: .idle
                ),
                pendingOperation: pendingOperation
            ),
            isPlayerPresented: true,
            providerSwitch: providerSwitch
        )
    }

    private func makeProvider(
        id: ProviderID,
        musicCapabilities: MusicProviderCapabilities
    ) -> ProviderDescriptor {
        ProviderDescriptor(
            id: id,
            name: "Future",
            musicCapabilities: musicCapabilities
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
