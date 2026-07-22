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
        await store.receive(
            .playback(
                .reset(
                    providerID: "future",
                    capabilities: futureCapabilities
                )
            )
        ) {
            $0.playback.pendingReset = .init(
                requestID: UUID(1),
                providerID: "future",
                capabilities: futureCapabilities
            )
        }
        await store.receive(.playback(.queue(.reset))) {
            $0.playback.queue = PlaybackQueueFeature.State(
                songs: [],
                currentItemID: nil
            )
        }
        await store.receive(.playback(.timeline(.reset))) {
            $0.playback.timeline = PlaybackTimelineFeature.State(
                confirmedPosition: 0,
                interaction: .idle
            )
        }
        await store.receive(
            .playback(
                .applyReset(requestID: UUID(1))
            )
        ) {
            $0.playback.providerID = "future"
            $0.playback.status = .idle
            $0.playback.failure = nil
            $0.playback.playbackEligibility = .unknown
            $0.playback.capabilities = futureCapabilities
            $0.playback.pendingOperation = nil
            $0.playback.pendingReset = nil
            $0.playback.isPlayerPresented = false
        }
        await store.receive(
            .playback(.delegate(.resetCompleted("future")))
        )
        await store.receive(.replaceProviderOwnedState("future")) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: nil
            )
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
        await store.receive(.playback(.task))
    }

    @Test
    func failedSwitchPreservesProviderOwnedState() async {
        let state = makeState()
        let store = makeStore(
            state: state,
            pause: { throw MusicProviderError.playbackFailed }
        )

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
        await store.receive(
            .providerSwitch(.pauseFailed(requestID: UUID(0)))
        )
        await store.receive(.providerSwitch(.delegate(.failed))) {
            $0.providerSwitch = nil
        }

        #expect(store.state.search == state.search)
        #expect(store.state.playback == state.playback)
        #expect(
            store.state.playback.isPlayerPresented
                == state.playback.isPlayerPresented
        )
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
            supportsQueueReplacement: true,
            supportsQueueTransitions: true
        )
    }

    private func makeStore(
        state: AppFeature.State? = nil,
        pause: (@Sendable () async throws -> Void)? = nil
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state ?? makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackTransport.pause = { try await Task.sleep(for: .seconds(60)) }
            $0.providerAccess.currentAccess = {
                return MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            }
            $0.playbackObservation.playbackSnapshots = {
                AsyncStream { $0.finish() }
            }
            if let pause {
                $0.playbackTransport.pause = pause
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
                pendingOperation: pendingOperation,
                pendingReset: nil,
                isPlayerPresented: true
            ),
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
