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
            $0.playbackObservation.playbackSnapshots = {
                AsyncStream { $0.finish() }
            }
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
        await store.receive(
            .playback(
                .reset(
                    providerID: .appleMusic,
                    capabilities: .allEnabled
                )
            )
        ) {
            $0.playback.pendingReset = .init(
                requestID: UUID(1),
                providerID: .appleMusic,
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
            $0.playback.providerID = .appleMusic
            $0.playback.pendingReset = nil
        }
        await store.receive(
            .playback(.delegate(.resetCompleted(.appleMusic)))
        )
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
        await store.receive(.playback(.task))
    }

    @Test
    func changedProviderConnectionCancelsPlaybackAndResetsProviderOwnedState() async {
        let song = makeSong()
        let queue = IdentifiedArray(uniqueElements: [song])
        let futureProvider = makeProvider(id: "future")
        let observationProbe = PlaybackObservationLifecycleProbe()
        let operationProbe = AppSuspendedPlaybackOperationProbe()
        let seekProbe = AppSuspendedPlaybackOperationProbe()
        let pendingOperation = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .paused
        )
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
                pendingOperation: .statusChange(pendingOperation),
                pendingReset: nil,
                isPlayerPresented: true
            )
        )
        let store = makeStore(state: state) {
            $0.playbackObservation.playbackSnapshots =
                observationProbe.playbackSnapshots
            $0.playbackControl.pause = operationProbe.callAsFunction
            $0.playbackControl.seek = seekProbe.callAsFunction
        }

        await store.send(.playback(.task))
        await observationProbe.waitForSubscription(1)
        await store.send(
            .playback(
                .performStatusChange(
                    requestID: pendingOperation.requestID,
                    target: pendingOperation.target
                )
            )
        )
        await operationProbe.waitUntilStarted()
        await store.send(.playback(.timeline(.dragEnded))) {
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
            $0.playback.pendingReset = .init(
                requestID: UUID(1),
                providerID: futureProvider.id,
                capabilities: futureProvider.musicCapabilities
            )
        }

        var playbackDuringReset = playbackBeforeReset
        playbackDuringReset.pendingReset = .init(
            requestID: UUID(1),
            providerID: futureProvider.id,
            capabilities: futureProvider.musicCapabilities
        )
        #expect(store.state.playback == playbackDuringReset)

        await observationProbe.waitForCancellation(1)
        await operationProbe.waitUntilCancelled()

        await store.receive(.playback(.queue(.reset))) {
            $0.playback.queue = .init(songs: [], currentItemID: nil)
        }
        await store.receive(.playback(.timeline(.reset))) {
            $0.playback.timeline = .init(
                confirmedPosition: 0,
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
            $0.playback.failure = nil
            $0.playback.playbackEligibility = .unknown
            $0.playback.capabilities = futureProvider.musicCapabilities
            $0.playback.pendingOperation = nil
            $0.playback.pendingReset = nil
            $0.playback.isPlayerPresented = false
        }
        await store.receive(
            .playback(.delegate(.resetCompleted(futureProvider.id)))
        )
        await store.receive(.replaceProviderOwnedState(futureProvider.id)) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: nil
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
            currentItemID: nil,
            status: .playing,
            currentTime: 27,
            playbackRate: .normal,
            repeatMode: .off,
            shuffleMode: .off
        )
        observationProbe.yield(replacementSnapshot, toSubscription: 2)
        await store.receive(.playback(.snapshotReceived(replacementSnapshot))) {
            $0.playback.status = .playing
        }
        await store.receive(.playback(.queue(.currentItemObserved(nil))))
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
        let pendingReset = PlaybackFeature.PendingReset(
            requestID: UUID(0),
            providerID: futureProvider.id,
            capabilities: futureProvider.musicCapabilities
        )
        var playback = makeState().playback
        playback.pendingReset = pendingReset
        let state = makeState(
            providers: [.appleMusic, futureProvider],
            connection: .connected(
                providerID: futureProvider.id,
                access: access
            ),
            playback: playback
        )
        let observationProbe = PlaybackObservationLifecycleProbe()
        let store = makeStore(state: state) {
            $0.playbackObservation.playbackSnapshots =
                observationProbe.playbackSnapshots
        }

        await store.send(
            .playback(
                .applyReset(requestID: UUID(0))
            )
        ) {
            $0.playback.providerID = futureProvider.id
            $0.playback.status = .idle
            $0.playback.failure = nil
            $0.playback.playbackEligibility = .unknown
            $0.playback.capabilities = futureProvider.musicCapabilities
            $0.playback.pendingOperation = nil
            $0.playback.pendingReset = nil
            $0.playback.isPlayerPresented = false
        }
        await store.receive(
            .playback(.delegate(.resetCompleted(futureProvider.id)))
        )
        await store.receive(.replaceProviderOwnedState(futureProvider.id)) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: access
            )
        }
        await store.receive(.playback(.task))
        await observationProbe.waitForSubscription(1)

        let snapshot = PlaybackSnapshot(
            currentItemID: nil,
            status: .paused,
            currentTime: 14,
            playbackRate: .normal,
            repeatMode: .off,
            shuffleMode: .off
        )
        observationProbe.yield(snapshot, toSubscription: 1)
        await store.receive(.playback(.snapshotReceived(snapshot))) {
            $0.playback.status = .paused
        }
        await store.receive(.playback(.queue(.currentItemObserved(nil))))
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
                    pendingOperation: nil,
                    pendingReset: nil,
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

private struct PlaybackObservationLifecycleProbe: Sendable {
    private let subscriptions: AsyncStream<Int>
    private let subscriptionsContinuation: AsyncStream<Int>.Continuation
    private let cancellations: AsyncStream<Int>
    private let cancellationsContinuation: AsyncStream<Int>.Continuation
    private let snapshotContinuations = LockIsolated<[AsyncStream<PlaybackSnapshot>.Continuation]>(
        [])

    init() {
        (subscriptions, subscriptionsContinuation) = AsyncStream<Int>.makeStream()
        (cancellations, cancellationsContinuation) = AsyncStream<Int>.makeStream()
    }

    func playbackSnapshots() async -> AsyncStream<PlaybackSnapshot> {
        return AsyncStream { continuation in
            let subscription = snapshotContinuations.withValue {
                $0.append(continuation)
                return $0.count
            }
            subscriptionsContinuation.yield(subscription)
            continuation.onTermination = { _ in
                cancellationsContinuation.yield(subscription)
            }
        }
    }

    func waitForSubscription(_ expectedSubscription: Int) async {
        var iterator = subscriptions.makeAsyncIterator()
        while let subscription = await iterator.next() {
            if subscription == expectedSubscription { return }
        }
    }

    func waitForCancellation(_ expectedSubscription: Int) async {
        var iterator = cancellations.makeAsyncIterator()
        while let subscription = await iterator.next() {
            if subscription == expectedSubscription { return }
        }
    }

    func yield(
        _ snapshot: PlaybackSnapshot,
        toSubscription subscription: Int
    ) {
        snapshotContinuations.value[subscription - 1].yield(snapshot)
    }

    func finish(subscription: Int) {
        snapshotContinuations.value[subscription - 1].finish()
    }
}

private struct AppSuspendedPlaybackOperationProbe: Sendable {
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let cancelled: AsyncStream<Void>
    private let cancelledContinuation: AsyncStream<Void>.Continuation
    private let pendingContinuation =
        LockIsolated<CheckedContinuation<Void, any Error>?>(nil)

    init() {
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
        (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
    }

    func callAsFunction() async throws {
        try await suspend()
    }

    func callAsFunction(_ position: TimeInterval) async throws {
        try await suspend()
    }

    private func suspend() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingContinuation.withValue { $0 = continuation }
                startedContinuation.yield()
            }
        } onCancel: {
            pendingContinuation.withValue { pendingContinuation in
                let continuation = pendingContinuation
                pendingContinuation = nil
                continuation?.resume(throwing: CancellationError())
            }
            cancelledContinuation.yield()
        }
    }

    func waitUntilStarted() async {
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        startedContinuation.finish()
    }

    func waitUntilCancelled() async {
        var iterator = cancelled.makeAsyncIterator()
        _ = await iterator.next()
        cancelledContinuation.finish()
    }
}
