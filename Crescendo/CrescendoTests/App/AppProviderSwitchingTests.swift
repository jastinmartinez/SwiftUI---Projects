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
                sourceProviderID: .testProvider,
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
        await store.send(.providerSelected(.testProvider))
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
                    sourceProviderID: .testProvider,
                    phase: .pausing(
                        targetProviderID: "future",
                        requestID: UUID(0)
                    )
                )
            )
        )

        await store.send(.providerSelected(.testProvider))
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
                    sourceProviderID: .testProvider,
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
        await store.send(.providerSelected(.testProvider))
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
                    sourceProviderID: .testProvider,
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
            $0.playback.pendingProviderReset = .init(
                requestID: UUID(1),
                providerID: "future",
                capabilities: futureCapabilities
            )
        }
        await store.receive(.playback(.queue(.reset))) {
            $0.playback.queue = PlaybackQueueFeature.State(
                tracks: [],
                playbackOrder: PlaybackQueueOrder(trackIDs: []),
                currentTrackID: nil,
                repeatMode: .off,
                shuffleMode: .off
            )
        }
        await store.receive(.playback(.timeline(.reset))) {
            $0.playback.timeline = PlaybackTimelineFeature.State(
                confirmedPosition: 0,
                duration: nil,
                isSeekable: false,
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
            $0.playback.failureNotice = nil
            $0.playback.playbackEligibility = .unknown
            $0.playback.capabilities = futureCapabilities
            $0.playback.pendingPlaybackTransition = nil
            $0.playback.pendingStatusChange = nil
            $0.playback.pendingProviderReset = nil
            $0.playback.isPlayerPresented = false
        }
        await store.receive(
            .playback(.delegate(.resetCompleted("future")))
        )
        await store.receive(.replaceProviderOwnedState("future")) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: nil,
                providerID: "future"
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
                sourceProviderID: .testProvider,
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
        let expectedPresentation = state.playback.isPlayerPresented
        #expect(store.state.playback.isPlayerPresented == expectedPresentation)
        #expect(store.state.providerConnection == state.providerConnection)
    }

    @Test
    func providerSelectionIsRejectedDuringAPendingPlaybackTransition() async {
        let song = makeTrack()
        let tracks = IdentifiedArray(uniqueElements: [song])
        let state = makeState(
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: tracks,
                targetTrackID: song.id
            )
        )
        let store = makeStore(state: state)

        await store.send(.providerSelected("future"))

        #expect(store.state == state)
    }

    @Test
    func searchResultTapIsRejectedDuringProviderSwitch() async {
        let song = makeTrack(nativeID: "next")
        let state = makeState(
            providerSwitch: ProviderSwitchFeature.State(
                sourceProviderID: .testProvider,
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
                    .trackTapped(
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
            supportsSeeking: false
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
            let accessClient = ProviderAccessClient(
                currentAccess: {
                    MusicProviderAccess(
                        authorization: .authorized,
                        playbackEligibility: .eligible
                    )
                },
                requestAccess: {
                    MusicProviderAccess(
                        authorization: .authorized,
                        playbackEligibility: .eligible
                    )
                }
            )
            $0.providerAccessClients = ProviderClientRegistry(
                clients: [
                    .testProvider: accessClient,
                    "future": accessClient,
                    "third": accessClient,
                ]
            )
            $0.playbackObservation.observations = {
                AsyncStream { $0.finish() }
            }
            if let pause {
                $0.playbackTransport.pause = pause
            }
        }
    }

    private func makeState(
        providerSwitch: ProviderSwitchFeature.State? = nil,
        pendingPlaybackTransition: PendingPlaybackTransition? = nil
    ) -> AppFeature.State {
        let song = makeTrack()
        let queue = IdentifiedArray(uniqueElements: [song])
        return AppFeature.State(
            providerConnection: ProviderConnectionFeature.State(
                providers: [
                    .testProvider,
                    makeProvider(
                        id: "future",
                        musicCapabilities: futureCapabilities
                    ),
                    makeProvider(id: "third", musicCapabilities: .allEnabled),
                ],
                connection: .connected(
                    providerID: .testProvider,
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
                        tracks: [makeTrack()],
                        nextCursor: nil,
                        status: .idle,
                        providerID: .testProvider
                    )
                ),
                providerAccess: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                ),
                providerID: .testProvider
            ),
            playback: PlaybackFeature.State(
                providerID: .testProvider,
                queue: PlaybackQueueFeature.State(
                    tracks: queue,
                    playbackOrder: PlaybackQueueOrder(trackIDs: Array(queue.ids)),
                    currentTrackID: song.id,
                    repeatMode: .off,
                    shuffleMode: .off
                ),
                status: .playing,
                failureNotice: nil,
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: 42,
                    duration: nil,
                    isSeekable: false,
                    interaction: .idle
                ),
                pendingPlaybackTransition: pendingPlaybackTransition,
                pendingStatusChange: nil,
                pendingProviderReset: nil,
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

    private func makeTrack(nativeID: String = "selected") -> Track {
        Track(
            id: .init(providerID: .testProvider, nativeID: nativeID),
            title: "Selected song",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
    }
}
