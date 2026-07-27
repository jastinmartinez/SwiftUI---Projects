import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppFeatureTests {
    @Test
    func taskStartsPlaybackObservationAndLeavesProviderDisconnected() async {
        let store = makeStore {
            $0.playbackObservation.observations = {
                AsyncStream { $0.finish() }
            }
        }

        await store.send(.task)
        await store.receive(.playback(.task))

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
            $0.providerAccessClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderAccessClient(
                        currentAccess: { access },
                        requestAccess: { access }
                    )
                ]
            )
            $0.playbackObservation.observations = {
                AsyncStream { $0.finish() }
            }
        }

        await store.send(.providerSelected(.testProvider))
        await store.receive(.providerConnection(.connect(.testProvider)))
        await store.receive(
            .providerConnection(.startConnection(.testProvider))
        ) {
            $0.providerConnection.connection = .connecting(
                providerID: .testProvider,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: .testProvider,
                        providerChanged: true
                    )
                )
            )
        )
        await store.receive(.resetProviderOwnedState(.testProvider))
        await store.receive(.search(.cancelSearch))
        await store.receive(
            .playback(
                .reset(
                    providerID: .testProvider,
                    capabilities: .allEnabled
                )
            )
        ) {
            $0.playback.pendingProviderReset = .init(
                requestID: UUID(1),
                providerID: .testProvider,
                capabilities: .allEnabled
            )
        }
        await store.receive(.playback(.queue(.reset)))
        await store.receive(.playback(.timeline(.reset)))
        await store.receive(
            .playback(
                .applyReset(requestID: UUID(1))
            )
        ) {
            $0.playback.providerID = .testProvider
            $0.playback.pendingProviderReset = nil
        }
        await store.receive(
            .playback(.delegate(.resetCompleted(.testProvider)))
        )
        await store.receive(.replaceProviderOwnedState(.testProvider))
        await store.receive(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(0),
                    providerID: .testProvider,
                    access: access
                )
            )
        )
        await store.receive(
            .providerConnection(
                .accessResolved(
                    requestID: UUID(0),
                    providerID: .testProvider,
                    access: access
                )
            )
        ) {
            $0.providerConnection.connection = .connected(
                providerID: .testProvider,
                access: access
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(
                            providerID: .testProvider,
                            access: access
                        )
                    )
                )
            )
        ) {
            $0.search.providerAccess = access
        }
        await store.receive(.playback(.task))
    }

    @Test
    func changedProviderConnectionCancelsPlaybackAndResetsProviderOwnedState() async {
        let song = makeTrack()
        let queue = IdentifiedArray(uniqueElements: [song])
        let futureProvider = makeProvider(id: "future")
        let observationProbe = PlaybackObservationLifecycleProbe()
        let operationProbe = SuspendedOperationProbe<Void>()
        let seekProbe = SuspendedOperationProbe<Void>()
        let pendingStatusChange = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .paused
        )
        let state = makeState(
            providers: [.testProvider, futureProvider],
            connection: .connecting(
                providerID: futureProvider.id,
                requestID: UUID(0)
            ),
            search: SearchFeature.State(
                query: song.title,
                status: .loaded(
                    SearchPaginationFeature.State(
                        tracks: queue,
                        nextCursor: nil,
                        status: .idle,
                        providerID: .testProvider
                    )
                ),
                providerAccess: .init(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                ),
                providerID: .testProvider
            ),
            playback: PlaybackFeature.State(
                providerID: .testProvider,
                queue: .init(
                    tracks: queue,
                    playbackOrder: PlaybackQueueOrder(trackIDs: Array(queue.ids)),
                    currentTrackID: song.id,
                    repeatMode: .off,
                    shuffleMode: .off
                ),
                status: .playing,
                failureNotice: PlaybackFailureNotice(
                    trackID: song.id,
                    failure: .playbackFailed
                ),
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: .init(
                    confirmedPosition: 42,
                    duration: nil,
                    interaction: .dragging(position: 50)
                ),
                pendingPlaybackTransition: nil,
                pendingStatusChange: pendingStatusChange,
                pendingProviderReset: nil,
                isPlayerPresented: true
            )
        )
        let store = makeStore(state: state) {
            $0.playbackObservation.observations =
                observationProbe.observations
            $0.playbackTransport.pause = operationProbe.run
            $0.playbackTimeline.seek = { _ in
                try await seekProbe.run()
            }
        }

        await store.send(.playback(.task))
        await observationProbe.waitForSubscription(1)
        await store.send(
            .playback(
                .performStatusChange(
                    requestID: pendingStatusChange.requestID,
                    target: pendingStatusChange.target
                )
            )
        )
        await operationProbe.waitUntilStarted()
        await store.send(.playback(.timeline(.dragEnded)))
        await store.receive(.playback(.timeline(.seekRequested(50)))) {
            $0.playback.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 50
            )
        }
        await seekProbe.waitUntilStarted()
        let playbackBeforeReset = store.state.playback

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
        await store.receive(
            .playback(
                .reset(
                    providerID: futureProvider.id,
                    capabilities: futureProvider.musicCapabilities
                )
            )
        ) {
            $0.playback.pendingProviderReset = .init(
                requestID: UUID(1),
                providerID: futureProvider.id,
                capabilities: futureProvider.musicCapabilities
            )
        }

        var playbackDuringReset = playbackBeforeReset
        playbackDuringReset.pendingProviderReset = .init(
            requestID: UUID(1),
            providerID: futureProvider.id,
            capabilities: futureProvider.musicCapabilities
        )
        #expect(store.state.playback == playbackDuringReset)

        await observationProbe.waitForCancellation(1)
        await operationProbe.waitUntilCancelled()

        await store.receive(.playback(.queue(.reset))) {
            $0.playback.queue = .init(
                tracks: [],
                playbackOrder: PlaybackQueueOrder(trackIDs: []),
                currentTrackID: nil,
                repeatMode: .off,
                shuffleMode: .off
            )
        }
        await store.receive(.playback(.timeline(.reset))) {
            $0.playback.timeline = .init(
                confirmedPosition: 0,
                duration: nil,
                interaction: .idle
            )
        }
        await store.receive(
            .playback(
                .applyReset(requestID: UUID(1))
            )
        ) {
            $0.playback.providerID = futureProvider.id
            $0.playback.status = .idle
            $0.playback.failureNotice = nil
            $0.playback.playbackEligibility = .unknown
            $0.playback.capabilities = futureProvider.musicCapabilities
            $0.playback.pendingPlaybackTransition = nil
            $0.playback.pendingStatusChange = nil
            $0.playback.pendingProviderReset = nil
            $0.playback.isPlayerPresented = false
        }
        await store.receive(
            .playback(.delegate(.resetCompleted(futureProvider.id)))
        )
        await store.receive(.replaceProviderOwnedState(futureProvider.id)) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: nil,
                providerID: futureProvider.id
            )
        }
        await seekProbe.waitUntilCancelled()

        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        await store.send(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(0),
                    providerID: futureProvider.id,
                    access: access
                )
            )
        )
        await store.receive(
            .providerConnection(
                .accessResolved(
                    requestID: UUID(0),
                    providerID: futureProvider.id,
                    access: access
                )
            )
        ) {
            $0.providerConnection.connection = .connected(
                providerID: futureProvider.id,
                access: access
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(
                            providerID: futureProvider.id,
                            access: access
                        )
                    )
                )
            )
        ) {
            $0.search.providerAccess = access
        }
        await store.receive(.playback(.task))
        await observationProbe.waitForSubscription(2)

        let replacementSnapshot = PlaybackSnapshot(
            currentTrackID: nil,
            status: .playing,
            position: 27,
            duration: nil
        )
        observationProbe.yield(replacementSnapshot, toSubscription: 2)
        await store.receive(
            .playback(.observationReceived(.snapshot(replacementSnapshot)))
        )
        await store.receive(.playback(.reconcileSnapshot(replacementSnapshot))) {
            $0.playback.status = .playing
        }
        await store.receive(.playback(.timeline(.positionObserved(27)))) {
            $0.playback.timeline.confirmedPosition = 27
        }

        observationProbe.finish(subscription: 2)
        await observationProbe.waitForCancellation(2)
        await store.finish()
    }

    @Test
    func resetCompletionStartsObservationWhenReplacementConnectedFirst() async {
        let futureProvider = makeProvider(id: "future")
        let access = MusicProviderAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: futureProvider.id,
            capabilities: futureProvider.musicCapabilities
        )
        var playback = makeState().playback
        playback.pendingProviderReset = pendingProviderReset
        let state = makeState(
            providers: [.testProvider, futureProvider],
            connection: .connected(
                providerID: futureProvider.id,
                access: access
            ),
            playback: playback
        )
        let observationProbe = PlaybackObservationLifecycleProbe()
        let store = makeStore(state: state) {
            $0.playbackObservation.observations =
                observationProbe.observations
        }

        await store.send(
            .playback(
                .applyReset(requestID: UUID(0))
            )
        ) {
            $0.playback.providerID = futureProvider.id
            $0.playback.status = .idle
            $0.playback.failureNotice = nil
            $0.playback.playbackEligibility = .unknown
            $0.playback.capabilities = futureProvider.musicCapabilities
            $0.playback.pendingPlaybackTransition = nil
            $0.playback.pendingStatusChange = nil
            $0.playback.pendingProviderReset = nil
            $0.playback.isPlayerPresented = false
        }
        await store.receive(
            .playback(.delegate(.resetCompleted(futureProvider.id)))
        )
        await store.receive(.replaceProviderOwnedState(futureProvider.id)) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: access,
                providerID: futureProvider.id
            )
        }
        await store.receive(.playback(.task))
        await observationProbe.waitForSubscription(1)

        let snapshot = PlaybackSnapshot(
            currentTrackID: nil,
            status: .paused,
            position: 14,
            duration: nil
        )
        observationProbe.yield(snapshot, toSubscription: 1)
        await store.receive(.playback(.observationReceived(.snapshot(snapshot))))
        await store.receive(.playback(.reconcileSnapshot(snapshot))) {
            $0.playback.status = .paused
        }
        await store.receive(.playback(.timeline(.positionObserved(14)))) {
            $0.playback.timeline.confirmedPosition = 14
        }

        observationProbe.finish(subscription: 1)
        await observationProbe.waitForCancellation(1)
        await store.finish()
    }

    @Test
    func unchangedProviderConnectionStartPreservesProviderOwnedState() async {
        let state = makeState(
            connection: .connecting(
                providerID: .testProvider,
                requestID: UUID(0)
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: .testProvider,
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
                providerAccess: access,
                providerID: .testProvider
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
        providers: [ProviderDescriptor] = [.testProvider],
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
                    providerAccess: nil,
                    providerID: .testProvider
                ),
            playback: playback
                ?? PlaybackFeature.State(
                    providerID: nil,
                    queue: .init(
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
                    timeline: .init(
                        confirmedPosition: 0,
                        duration: nil,
                        interaction: .idle
                    ),
                    pendingPlaybackTransition: nil,
                    pendingStatusChange: nil,
                    pendingProviderReset: nil,
                    isPlayerPresented: isPlayerPresented
                ),
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
                supportsSeeking: false
            )
        )
    }

    private func makeTrack() -> Track {
        Track(
            id: .init(providerID: .testProvider, nativeID: "selected"),
            title: "Selected song",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: 180
        )
    }
}
