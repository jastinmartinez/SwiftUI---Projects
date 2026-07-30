import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackFeatureTests {
    @Test
    func taskSubscribesToPlaybackObservationsOnce() async {
        let subscriptionCount = LockIsolated(0)
        let snapshot = makeSnapshot(
            trackID: nil,
            status: .paused,
            position: 2,
            duration: 20,
            isSeekable: true
        )
        let store = makeStore {
            $0.playbackObservation.observations = {
                subscriptionCount.withValue { $0 += 1 }
                return AsyncStream { continuation in
                    continuation.yield(.snapshot(snapshot))
                    continuation.finish()
                }
            }
        }

        await store.send(.task)
        await store.receive(.observationReceived(.snapshot(snapshot)))
        await store.receive(.confirmedSnapshotReceived(snapshot))
        await store.receive(
            .timeline(
                .confirmedSnapshot(
                    position: 2,
                    duration: 20,
                    isSeekable: true
                )
            )
        ) {
            $0.timeline.confirmedPosition = 2
            $0.timeline.duration = 20
            $0.timeline.isSeekable = true
        }
        await store.receive(
            .session(
                .confirmedSnapshot(
                    status: .paused,
                    position: 2
                )
            )
        ) {
            $0.session.status = .paused
        }

        #expect(subscriptionCount.value == 1)
    }

    @Test
    func firstSelectionRoutesThroughQueueAndCreatesTransition() async {
        let tracks = makeTracks(prefix: "selected")
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let loadedTrackIDs = LockIsolated<[TrackID]>([])
        let loadedURLs = LockIsolated<[URL]>([])
        let store = makeStore {
            $0.playbackItem.load = { trackID, playbackURL, _ in
                loadedTrackIDs.withValue { $0.append(trackID) }
                loadedURLs.withValue { $0.append(playbackURL) }
                throw CancellationError()
            }
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults
            )
        )
        await store.receive(
            .queue(
                .selectionRequested(
                    tracks[1].id,
                    loadedResults: loadedResults
                )
            )
        ) {
            $0.queue.pendingChanges = .init(
                active: replacementChange(
                    loadedResults,
                    startingAt: tracks[1].id
                ),
                followUp: nil
            )
        }
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[1].id)))
        ) {
            $0.transition = PlaybackTransitionFeature.State(
                phase: .starting(
                    .init(
                        target: tracks[1],
                        baselineTrackID: nil
                    )
                )
            )
            $0.failureNotice = nil
            $0.isPlayerPresented = true
        }
        await store.receive(.session(.cancelPendingStatusChange))
        await store.receive(.transition(.start)) {
            $0.transition?.phase = .preparing(
                self.transaction(
                    target: tracks[1],
                    baselineTrackID: nil
                ),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.finish()

        #expect(loadedTrackIDs.value == [tracks[1].id])
        #expect(loadedURLs.value == [tracks[1].playbackURL])
        #expect(store.state.queue.current == nil)
        #expect(store.state.queue.pendingTrack == tracks[1])
    }

    @Test
    func selectionCancelsThePendingSessionOperation() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let queue = makeQueue(
            pendingChanges: .init(
                active: replacementChange(
                    loadedResults,
                    startingAt: tracks[1].id
                ),
                followUp: nil
            )
        )
        let store = makeStore(
            queue: queue,
            session: .init(
                status: .playing,
                pendingStatusChange: .init(
                    requestID: UUID(9),
                    target: .paused
                )
            )
        )

        await store.send(
            .queue(.delegate(.transitionRequested(tracks[1].id)))
        ) {
            $0.transition = .init(
                phase: .starting(
                    .init(
                        target: tracks[1],
                        baselineTrackID: nil
                    )
                )
            )
            $0.isPlayerPresented = true
        }
        await store.receive(.session(.cancelPendingStatusChange)) {
            $0.session.pendingStatusChange = nil
        }
        await store.receive(.transition(.start)) {
            $0.transition?.phase = .preparing(
                self.transaction(
                    target: tracks[1],
                    baselineTrackID: nil
                ),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.finish()
    }

    @Test
    func queueDelegateCreatesANavigationTransition() async {
        let tracks = makeTracks()
        let loadedURLs = LockIsolated<[URL]>([])
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            session: .init(
                status: .playing,
                pendingStatusChange: nil
            )
        ) {
            $0.playbackItem.load = { _, playbackURL, _ in
                loadedURLs.withValue { $0.append(playbackURL) }
                throw CancellationError()
            }
        }

        await store.send(.nextTapped)
        await store.receive(.queue(.nextTapped)) {
            $0.queue.pendingChanges = .init(
                active: .navigation(to: tracks[1].id),
                followUp: nil
            )
        }
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[1].id)))
        ) {
            $0.transition = .init(
                phase: .starting(
                    .init(
                        target: tracks[1],
                        baselineTrackID: tracks[0].id
                    )
                )
            )
        }
        await store.receive(.session(.cancelPendingStatusChange))
        await store.receive(.transition(.start)) {
            $0.transition?.phase = .preparing(
                self.transaction(
                    target: tracks[1],
                    baselineTrackID: tracks[0].id
                ),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.finish()
        #expect(loadedURLs.value == [tracks[1].playbackURL])
    }

    @Test
    func laterSelectionSupersedesWithoutPresentingAgain() async {
        let confirmedTracks = makeTracks(prefix: "confirmed")
        let firstTracks = makeTracks(prefix: "first")
        let firstResults = IdentifiedArray(uniqueElements: firstTracks)
        let latestTracks = makeTracks(prefix: "latest")
        let latestResults = IdentifiedArray(uniqueElements: latestTracks)
        let firstIntent = PlaybackTransitionFeature.Intent(
            target: firstTracks[0],
            baselineTrackID: confirmedTracks[0].id
        )
        let queue = makeQueue(
            tracks: confirmedTracks,
            currentTrackID: confirmedTracks[0].id,
            pendingChanges: .init(
                active: replacementChange(
                    firstResults,
                    startingAt: firstTracks[0].id
                ),
                followUp: nil
            )
        )
        let store = makeStore(
            queue: queue,
            transition: .init(phase: .starting(firstIntent))
        )

        await store.send(
            .selectionReceived(
                latestTracks[2].id,
                loadedResults: latestResults
            )
        )
        await store.receive(
            .queue(
                .selectionRequested(
                    latestTracks[2].id,
                    loadedResults: latestResults
                )
            )
        ) {
            $0.queue.pendingChanges?.followUp = replacementChange(
                latestResults,
                startingAt: latestTracks[2].id
            )
        }
        await store.receive(
            .queue(.delegate(.transitionRequested(latestTracks[2].id)))
        )
        await store.receive(.session(.cancelPendingStatusChange))
        let latestIntent = PlaybackTransitionFeature.Intent(
            target: latestTracks[2],
            baselineTrackID: confirmedTracks[0].id
        )
        await store.receive(.transition(.supersede(latestIntent))) {
            $0.transition?.phase = .starting(latestIntent)
        }
        await store.receive(.transition(.start)) {
            $0.transition?.phase = .preparing(
                self.transaction(
                    target: latestTracks[2],
                    baselineTrackID: confirmedTracks[0].id
                ),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.finish()

        #expect(!store.state.isPlayerPresented)
        #expect(
            store.state.queue.current?.currentTrackID
                == confirmedTracks[0].id
        )
        #expect(store.state.queue.pendingTrack == latestTracks[2])
    }

    @Test
    func missingSelectionCreatesNoTransition() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let missingTrackID = TrackID(
            providerID: "fake",
            nativeID: "missing"
        )
        let store = makeStore()

        await store.send(
            .selectionReceived(
                missingTrackID,
                loadedResults: loadedResults
            )
        )
        await store.receive(
            .queue(
                .selectionRequested(
                    missingTrackID,
                    loadedResults: loadedResults
                )
            )
        )

        #expect(store.state.transition == nil)
        #expect(store.state.queue.pendingChanges == nil)
        #expect(!store.state.isPlayerPresented)
    }

    @Test
    func stableSnapshotRoutesQueueTimelineAndSession() async {
        let tracks = makeTracks()
        let snapshot = makeSnapshot(
            trackID: tracks[1].id,
            status: .paused,
            position: 42,
            duration: 180,
            isSeekable: true
        )
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            session: .init(
                status: .playing,
                pendingStatusChange: nil
            )
        )

        await store.send(.confirmedSnapshotReceived(snapshot))
        await store.receive(
            .queue(.currentTrackConfirmed(tracks[1].id))
        ) {
            $0.queue.current = $0.queue.current?.navigating(
                to: tracks[1].id
            )
        }
        await store.receive(
            .timeline(
                .confirmedSnapshot(
                    position: 42,
                    duration: 180,
                    isSeekable: true
                )
            )
        ) {
            $0.timeline.confirmedPosition = 42
            $0.timeline.duration = 180
            $0.timeline.isSeekable = true
        }
        await store.receive(
            .session(
                .confirmedSnapshot(
                    status: .paused,
                    position: 42
                )
            )
        ) {
            $0.session.status = .paused
        }
    }

    @Test
    func activeTransitionReceivesTargetSnapshotBeforeDurableChildren()
        async
    {
        let tracks = makeTracks()
        let intent = PlaybackTransitionFeature.Intent(
            target: tracks[1],
            baselineTrackID: tracks[0].id
        )
        let transaction = PlaybackTransitionFeature.Transaction(
            requestID: UUID(9),
            intent: intent
        )
        let snapshot = makeSnapshot(
            trackID: tracks[1].id,
            status: .waiting,
            position: 3
        )
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            transition: .init(
                phase: .preparing(
                    transaction,
                    .init(stage: .loading, latestTargetSnapshot: nil)
                )
            )
        )

        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.transition(.snapshotReceived(snapshot))) {
            $0.transition?.phase = .preparing(
                transaction,
                .init(
                    stage: .loading,
                    latestTargetSnapshot: snapshot
                )
            )
        }

        #expect(
            store.state.queue.current?.currentTrackID == tracks[0].id
        )
        #expect(store.state.timeline.confirmedPosition == 0)
        #expect(store.state.session.status == .idle)
    }

    @Test
    func transitionBaselineSnapshotRoutesToDurableChildren() async {
        let tracks = makeTracks()
        let intent = PlaybackTransitionFeature.Intent(
            target: tracks[1],
            baselineTrackID: tracks[0].id
        )
        let snapshot = makeSnapshot(
            trackID: tracks[0].id,
            status: .playing,
            position: 14,
            duration: 180,
            isSeekable: true
        )
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            transition: .init(phase: .starting(intent))
        )

        await store.send(
            .transition(
                .delegate(.confirmedSnapshotReady(snapshot))
            )
        )
        await store.receive(.confirmedSnapshotReceived(snapshot))
        await store.receive(
            .queue(.currentTrackConfirmed(tracks[0].id))
        )
        await store.receive(
            .timeline(
                .confirmedSnapshot(
                    position: 14,
                    duration: 180,
                    isSeekable: true
                )
            )
        ) {
            $0.timeline.confirmedPosition = 14
            $0.timeline.duration = 180
            $0.timeline.isSeekable = true
        }
        await store.receive(
            .session(
                .confirmedSnapshot(
                    status: .playing,
                    position: 14
                )
            )
        ) {
            $0.session.status = .playing
        }
    }

    @Test
    func transitionConfirmationRoutesQueueTimelineSessionThenAcknowledges()
        async
    {
        let confirmedTracks = makeTracks(prefix: "confirmed")
        let selectedTracks = makeTracks(prefix: "selected")
        let loadedResults = IdentifiedArray(uniqueElements: selectedTracks)
        let intent = PlaybackTransitionFeature.Intent(
            target: selectedTracks[1],
            baselineTrackID: confirmedTracks[0].id
        )
        let transaction = PlaybackTransitionFeature.Transaction(
            requestID: UUID(9),
            intent: intent
        )
        let snapshot = makeSnapshot(
            trackID: selectedTracks[1].id,
            status: .playing,
            position: 4,
            duration: 180,
            isSeekable: true
        )
        let confirmation = PlaybackTransitionFeature.Confirmation(
            intent: intent,
            snapshot: snapshot
        )
        let store = makeStore(
            queue: makeQueue(
                tracks: confirmedTracks,
                currentTrackID: confirmedTracks[0].id,
                pendingChanges: .init(
                    active: replacementChange(
                        loadedResults,
                        startingAt: selectedTracks[1].id
                    ),
                    followUp: nil
                )
            ),
            transition: .init(
                phase: .applyingConfirmation(
                    transaction,
                    .init(snapshot: snapshot, followUp: nil)
                )
            )
        )

        await store.send(
            .transition(.delegate(.confirmationReady(confirmation)))
        )
        await store.receive(
            .queue(.pendingChangeConfirmed(selectedTracks[1].id))
        ) {
            $0.queue.current = makeConfirmedQueue(
                loadedResults,
                startingAt: selectedTracks[1].id
            )
            $0.queue.pendingChanges = nil
        }
        await store.receive(
            .timeline(
                .confirmedSnapshot(
                    position: 4,
                    duration: 180,
                    isSeekable: true
                )
            )
        ) {
            $0.timeline.confirmedPosition = 4
            $0.timeline.duration = 180
            $0.timeline.isSeekable = true
        }
        await store.receive(
            .session(
                .confirmedSnapshot(
                    status: .playing,
                    position: 4
                )
            )
        ) {
            $0.session.status = .playing
        }
        await store.receive(.transition(.confirmationApplied))
        await store.receive(
            .transition(.delegate(.completed(.confirmed)))
        ) {
            $0.transition = nil
        }
    }

    @Test
    func cancelledTransitionClearsItsPendingQueueChanges() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let intent = PlaybackTransitionFeature.Intent(
            target: tracks[1],
            baselineTrackID: nil
        )
        let store = makeStore(
            queue: makeQueue(
                pendingChanges: .init(
                    active: replacementChange(
                        loadedResults,
                        startingAt: tracks[1].id
                    ),
                    followUp: nil
                )
            ),
            transition: .init(phase: .starting(intent))
        )

        await store.send(
            .transition(.delegate(.completed(.cancelled)))
        ) {
            $0.transition = nil
        }
        await store.receive(.queue(.pendingChangesDiscarded)) {
            $0.queue.pendingChanges = nil
        }
    }

    @Test
    func failedTransitionClearsPendingQueueChangesAndSurfacesFailure()
        async
    {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let intent = PlaybackTransitionFeature.Intent(
            target: tracks[1],
            baselineTrackID: nil
        )
        let store = makeStore(
            queue: makeQueue(
                pendingChanges: .init(
                    active: replacementChange(
                        loadedResults,
                        startingAt: tracks[1].id
                    ),
                    followUp: nil
                )
            ),
            transition: .init(phase: .starting(intent))
        )

        await store.send(
            .transition(
                .delegate(
                    .completed(
                        .failed(
                            trackID: tracks[1].id,
                            failure: .playbackFailed
                        )
                    )
                )
            )
        ) {
            $0.transition = nil
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[1].id,
                failure: .playbackFailed
            )
        }
        await store.receive(.queue(.pendingChangesDiscarded)) {
            $0.queue.pendingChanges = nil
        }
    }

    @Test
    func stableCompletionRoutesThroughQueuePolicy() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            session: .init(
                status: .playing,
                pendingStatusChange: nil
            )
        )

        await store.send(
            .observationReceived(.completed(tracks[0].id))
        )
        await store.receive(
            .queue(.currentTrackCompleted(tracks[0].id))
        ) {
            $0.queue.pendingChanges = .init(
                active: .navigation(to: tracks[1].id),
                followUp: nil
            )
        }
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[1].id)))
        ) {
            $0.transition = .init(
                phase: .starting(
                    .init(
                        target: tracks[1],
                        baselineTrackID: tracks[0].id
                    )
                )
            )
        }
        await store.receive(.session(.cancelPendingStatusChange))
        await store.receive(.transition(.start)) {
            $0.transition?.phase = .preparing(
                self.transaction(
                    target: tracks[1],
                    baselineTrackID: tracks[0].id
                ),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.finish()
    }

    @Test
    func delayedCompletionCannotReplaceAnActiveTransition() async {
        let tracks = makeTracks()
        let intent = PlaybackTransitionFeature.Intent(
            target: tracks[1],
            baselineTrackID: tracks[0].id
        )
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            transition: .init(phase: .starting(intent))
        )
        let initialState = store.state

        await store.send(
            .observationReceived(.completed(tracks[0].id))
        )

        #expect(store.state == initialState)
    }

    @Test
    func transitionRuntimeFailureRoutesToTransitionFirst() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let intent = PlaybackTransitionFeature.Intent(
            target: tracks[1],
            baselineTrackID: nil
        )
        let store = makeStore(
            queue: makeQueue(
                pendingChanges: .init(
                    active: replacementChange(
                        loadedResults,
                        startingAt: tracks[1].id
                    ),
                    followUp: nil
                )
            ),
            transition: .init(phase: .starting(intent))
        )

        await store.send(
            .observationReceived(
                .failed(tracks[1].id, .playbackFailed)
            )
        )
        await store.receive(
            .transition(
                .runtimeFailureReceived(
                    tracks[1].id,
                    .playbackFailed
                )
            )
        )
        await store.receive(
            .transition(
                .delegate(
                    .completed(
                        .failed(
                            trackID: tracks[1].id,
                            failure: .playbackFailed
                        )
                    )
                )
            )
        ) {
            $0.transition = nil
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[1].id,
                failure: .playbackFailed
            )
        }
        await store.receive(.queue(.pendingChangesDiscarded)) {
            $0.queue.pendingChanges = nil
        }
    }

    @Test
    func transitionStopReadyDiscardsQueueChangesThenStopsSession() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let intent = PlaybackTransitionFeature.Intent(
            target: tracks[1],
            baselineTrackID: tracks[0].id
        )
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id,
                pendingChanges: .init(
                    active: replacementChange(
                        loadedResults,
                        startingAt: tracks[1].id
                    ),
                    followUp: nil
                )
            ),
            timeline: .init(
                confirmedPosition: 12,
                duration: 180,
                isSeekable: true,
                interaction: .idle
            ),
            session: .init(
                status: .playing,
                pendingStatusChange: nil
            ),
            transition: .init(phase: .starting(intent))
        ) {
            $0.playbackTransport.stop = { .completed }
        }

        await store.send(
            .transition(.delegate(.completed(.stopReady)))
        ) {
            $0.transition = nil
        }
        await store.receive(.queue(.pendingChangesDiscarded)) {
            $0.queue.pendingChanges = nil
        }
        await store.receive(.session(.stopRequested)) {
            $0.session.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .stopped
            )
        }
        await store.receive(
            .session(.statusCommandSucceeded(requestID: UUID(0)))
        ) {
            $0.session.status = .stopped
            $0.session.pendingStatusChange = nil
        }
        await store.receive(.session(.delegate(.stopCompleted)))
        await store.receive(.timeline(.resetPosition)) {
            $0.timeline.confirmedPosition = 0
            $0.timeline.interaction = .idle
        }
    }

    @Test
    func timelineIntentClampsToConfirmedDuration() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            timeline: .init(
                confirmedPosition: 20,
                duration: 100,
                isSeekable: true,
                interaction: .idle
            )
        )

        await store.send(.timelinePositionChanged(-20))
        await store.receive(.timeline(.positionChanged(0))) {
            $0.timeline.interaction = .dragging(position: 0)
        }
        await store.send(.timelinePositionChanged(120))
        await store.receive(.timeline(.positionChanged(100))) {
            $0.timeline.interaction = .dragging(position: 100)
        }
    }

    @Test
    func timelineInteractionEndClampsDraftBeforeSeeking() async {
        let tracks = makeTracks()
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            timeline: .init(
                confirmedPosition: 20,
                duration: 100,
                isSeekable: true,
                interaction: .dragging(position: 120)
            )
        ) {
            $0.playbackTimeline.seek = { position in
                seekPositions.withValue { $0.append(position) }
                return .completed
            }
        }

        await store.send(.timelineInteractionEnded)
        await store.receive(.timeline(.positionChanged(100))) {
            $0.timeline.interaction = .dragging(position: 100)
        }
        await store.receive(.timeline(.dragEnded))
        await store.receive(.timeline(.seekRequested(100))) {
            $0.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 100
            )
        }
        await store.receive(
            .timeline(.seekSucceeded(requestID: UUID(0)))
        ) {
            $0.timeline.confirmedPosition = 100
            $0.timeline.interaction = .idle
        }

        #expect(seekPositions.value == [100])
    }

    @Test
    func unseekableTimelineRejectsEveryTimelineCommand() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            ),
            timeline: .init(
                confirmedPosition: 20,
                duration: 100,
                isSeekable: false,
                interaction: .idle
            )
        )
        let initialState = store.state

        await store.send(.timelinePositionChanged(40))
        await store.send(.timelineInteractionEnded)
        await store.send(.restartTapped)
        await store.send(.seekBackwardTapped)
        await store.send(.seekForwardTapped)

        #expect(store.state == initialState)
    }

    @Test
    func stableRuntimeFailureRequiresTheConfirmedIdentity() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            )
        )

        await store.send(
            .observationReceived(
                .failed(tracks[1].id, .playbackFailed)
            )
        )
        await store.send(
            .observationReceived(
                .failed(tracks[0].id, .playbackFailed)
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[0].id,
                failure: .playbackFailed
            )
        }
    }

    @Test
    func timelineFailureUsesTheConfirmedQueueIdentity() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: makeQueue(
                tracks: tracks,
                currentTrackID: tracks[0].id
            )
        )

        await store.send(
            .timeline(.delegate(.transportFailed(.playbackFailed)))
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[0].id,
                failure: .playbackFailed
            )
        }
    }

    // MARK: - Helpers

    private func makeStore(
        queue: PlaybackQueueFeature.State = .init(
            current: nil
        ),
        timeline: PlaybackTimelineFeature.State = .init(
            confirmedPosition: 0,
            duration: nil,
            isSeekable: false,
            interaction: .idle
        ),
        session: PlaybackSessionFeature.State = .init(
            status: .idle,
            pendingStatusChange: nil
        ),
        transition: PlaybackTransitionFeature.State? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackFeature> {
        TestStore(
            initialState: PlaybackFeature.State(
                queue: queue,
                timeline: timeline,
                session: session,
                transition: transition,
                failureNotice: nil,
                isPlayerPresented: false
            )
        ) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackObservation.observations = { .finished }
            $0.playbackItem.load = { _, _, _ in
                throw CancellationError()
            }
            $0.playbackItem.rollback = { _ in }
            configureDependencies(&$0)
        }
    }

    private func makeQueue(
        tracks: [Track] = [],
        currentTrackID: TrackID? = nil,
        pendingChanges: PlaybackQueueFeature.PendingChanges? = nil
    ) -> PlaybackQueueFeature.State {
        PlaybackQueueFeature.State(
            current: makeConfirmedQueue(
                tracks,
                currentTrackID: currentTrackID
            ),
            pendingChanges: pendingChanges
        )
    }

    private func replacementChange(
        _ tracks: IdentifiedArrayOf<Track>,
        startingAt trackID: TrackID
    ) -> PlaybackQueueFeature.QueueChange {
        .replacement(
            makeConfirmedQueue(
                tracks,
                startingAt: trackID
            )
        )
    }

    private func makeConfirmedQueue(
        _ tracks: IdentifiedArrayOf<Track>,
        startingAt trackID: TrackID
    ) -> PlaybackQueue {
        guard
            let queue = PlaybackQueue(
                tracks: tracks,
                startingAt: trackID
            )
        else {
            preconditionFailure("Expected a valid playback queue fixture")
        }
        return queue
    }

    private func makeConfirmedQueue(
        _ tracks: [Track],
        currentTrackID: TrackID?
    ) -> PlaybackQueue? {
        guard !tracks.isEmpty else { return nil }
        guard let currentTrackID else {
            preconditionFailure(
                "A non-empty playback queue fixture needs a current track"
            )
        }
        return makeConfirmedQueue(
            IdentifiedArray(uniqueElements: tracks),
            startingAt: currentTrackID
        )
    }

    private func transaction(
        target: Track,
        baselineTrackID: TrackID?
    ) -> PlaybackTransitionFeature.Transaction {
        PlaybackTransitionFeature.Transaction(
            requestID: UUID(0),
            intent: .init(
                target: target,
                baselineTrackID: baselineTrackID
            )
        )
    }

    private func makeTracks(prefix: String = "track") -> [Track] {
        [
            makeTrack(nativeID: "\(prefix)-1"),
            makeTrack(nativeID: "\(prefix)-2"),
            makeTrack(nativeID: "\(prefix)-3"),
        ]
    }

    private func makeTrack(nativeID: String) -> Track {
        Track(
            id: TrackID(providerID: "fake", nativeID: nativeID),
            title: nativeID,
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: 180
        )
    }

    private func makeSnapshot(
        trackID: TrackID?,
        status: PlaybackStatus,
        position: TimeInterval,
        duration: TimeInterval? = nil,
        isSeekable: Bool = false
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            currentTrackID: trackID,
            status: status,
            position: position,
            duration: duration,
            isSeekable: isSeekable
        )
    }
}
