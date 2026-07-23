import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackQueueFeatureTests {
    @Test
    func replacementStoresTheFrozenOrderAndStartingItem() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore()

        await store.send(.replace(queue, startingAt: tracks[1].id)) {
            $0.tracks = queue
            $0.currentTrackID = tracks[1].id
        }

        #expect(store.state.currentTrack == tracks[1])
    }

    @Test
    func observedQueueItemUpdatesTheCurrentIdentity() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        )

        await store.send(.currentItemObserved(tracks[1].id)) {
            $0.currentTrackID = tracks[1].id
        }

        #expect(store.state.currentTrack == tracks[1])
    }

    @Test(arguments: [
        TrackID(providerID: "fake", nativeID: "unknown"),
        TrackID(providerID: "other", nativeID: "1"),
    ])
    func unknownObservedItemPreservesTheCurrentItem(
        observedItemID: TrackID
    ) async {
        let tracks = makeTracks()
        let state = PlaybackQueueFeature.State(
            tracks: .init(uniqueElements: tracks),
            currentTrackID: tracks[0].id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
        let store = TestStore(initialState: state) {
            PlaybackQueueFeature()
        }

        await store.send(.currentItemObserved(observedItemID))

        #expect(store.state == state)
        #expect(store.state.currentTrack == tracks[0])
    }

    @Test
    func missingObservedItemPreservesTheCurrentItem() async {
        let tracks = makeTracks()
        let state = PlaybackQueueFeature.State(
            tracks: .init(uniqueElements: tracks),
            currentTrackID: tracks[0].id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
        let store = TestStore(initialState: state) {
            PlaybackQueueFeature()
        }

        await store.send(.currentItemObserved(nil))

        #expect(store.state == state)
        #expect(store.state.currentTrack == tracks[0])
    }

    @Test
    func resetEmptiesTheQueueAndCurrentIdentity() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .all,
            shuffleMode: .songs,
            pendingQueueTransition: .init(
                requestID: UUID(0),
                direction: .next
            ),
            pendingRepeatChange: .init(
                requestID: UUID(1),
                target: .one
            ),
            pendingShuffleChange: .init(
                requestID: UUID(2),
                target: .off
            )
        )

        await store.send(.reset) {
            $0.tracks = []
            $0.currentTrackID = nil
            $0.repeatMode = .off
            $0.shuffleMode = .off
            $0.pendingQueueTransition = nil
            $0.pendingRepeatChange = nil
            $0.pendingShuffleChange = nil
        }

        #expect(store.state.currentTrack == nil)
    }

    @Test(arguments: [
        PlaybackQueueNavigationDirection.previous,
        .next,
    ])
    func queueTransitionCallsOnlyTheRequestedCapabilityAndWaitsForObservation(
        direction: PlaybackQueueNavigationDirection
    ) async {
        let tracks = makeTracks()
        let calls = LockIsolated<[PlaybackQueueNavigationDirection]>([])
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[1].id
        ) {
            $0.playbackQueue.navigate = { direction in
                calls.withValue { $0.append(direction) }
                return .accepted
            }
        }

        await store.send(.queueTransitionRequested(direction)) {
            $0.pendingQueueTransition = .init(
                requestID: UUID(0),
                direction: direction
            )
        }
        await store.finish()

        #expect(calls.value == [direction])
        #expect(store.state.currentTrackID == tracks[1].id)
        #expect(store.state.pendingQueueTransition != nil)
    }

    @Test
    func observedChangedItemConfirmsThePendingQueueTransition() async {
        let tracks = makeTracks()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(0),
            direction: .next
        )
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            pendingQueueTransition: pending
        )

        await store.send(.currentItemObserved(tracks[1].id)) {
            $0.currentTrackID = tracks[1].id
            $0.pendingQueueTransition = nil
        }
    }

    @Test
    func unchangedOrUnknownObservationDoesNotConfirmAQueueTransition() async {
        let tracks = makeTracks()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(7),
            direction: .next
        )
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            pendingQueueTransition: pending
        )

        await store.send(.currentItemObserved(tracks[0].id))
        await store.send(
            .currentItemObserved(
                TrackID(providerID: "fake", nativeID: "unknown")
            )
        )

        #expect(store.state.currentTrackID == tracks[0].id)
        #expect(store.state.pendingQueueTransition == pending)
    }

    @Test
    func unresolvedQueueTransitionRejectsAnotherRequest() async {
        let tracks = makeTracks()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(7),
            direction: .next
        )
        let calls = LockIsolated(0)
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            pendingQueueTransition: pending
        ) {
            $0.playbackQueue.navigate = { _ in
                calls.withValue { $0 += 1 }
                return .accepted
            }
        }

        await store.send(.queueTransitionRequested(.previous))

        #expect(store.state.pendingQueueTransition == pending)
        #expect(calls.value == 0)
    }

    @Test
    func staleQueueTransitionFailureCannotClearTheActiveRequest() async {
        let tracks = makeTracks()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(1),
            direction: .next
        )
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            pendingQueueTransition: pending
        )

        await store.send(
            .queueTransitionFailed(
                requestID: UUID(0),
                error: .playbackFailed
            )
        )

        #expect(store.state.pendingQueueTransition == pending)
    }

    @Test
    func matchingQueueTransitionFailureClearsOnlyTheOperationAndDelegatesError() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        ) {
            $0.playbackQueue.navigate = { direction in
                #expect(direction == .next)
                throw MusicProviderError.playbackFailed
            }
        }

        await store.send(.queueTransitionRequested(.next)) {
            $0.pendingQueueTransition = .init(
                requestID: UUID(0),
                direction: .next
            )
        }
        await store.receive(
            .queueTransitionFailed(
                requestID: UUID(0),
                error: .playbackFailed
            )
        ) {
            $0.pendingQueueTransition = nil
        }
        await store.receive(.delegate(.queueTransitionFailed(.playbackFailed)))

        #expect(store.state.currentTrackID == tracks[0].id)
    }

    @Test
    func queueBoundaryClearsTheOperationWithoutDelegatingFailure() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        ) {
            $0.playbackQueue.navigate = { direction in
                #expect(direction == .previous)
                return .boundaryReached
            }
        }

        await store.send(.queueTransitionRequested(.previous)) {
            $0.pendingQueueTransition = .init(
                requestID: UUID(0),
                direction: .previous
            )
        }
        await store.receive(
            .queueTransitionReachedBoundary(requestID: UUID(0))
        ) {
            $0.pendingQueueTransition = nil
        }

        #expect(store.state.currentTrackID == tracks[0].id)
    }

    @Test
    func resetCancelsAnExecutingQueueTransition() async {
        let tracks = makeTracks()
        let probe =
            SuspendedOperationProbe<PlaybackQueueNavigationResult>()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        ) {
            $0.playbackQueue.navigate = { direction in
                #expect(direction == .next)
                return try await probe.run()
            }
        }

        await store.send(.queueTransitionRequested(.next)) {
            $0.pendingQueueTransition = .init(
                requestID: UUID(0),
                direction: .next
            )
        }
        await probe.waitUntilStarted()
        await store.send(.reset) {
            $0.tracks = []
            $0.currentTrackID = nil
            $0.pendingQueueTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func repeatCycleSelectsTheNextSupportedMode() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .off
        ) {
            $0.playbackQueue.setRepeat = { _ in }
        }

        await store.send(.cycleRepeatModeRequested([.off, .one]))
        await store.receive(.repeatModeChangeRequested(.one)) {
            $0.pendingRepeatChange = .init(
                requestID: UUID(0),
                target: .one
            )
        }
        await store.receive(.repeatModeChangeSucceeded(requestID: UUID(0))) {
            $0.repeatMode = .one
            $0.pendingRepeatChange = nil
        }
    }

    @Test
    func repeatCycleWrapsAndSkipsUnsupportedModes() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .one
        ) {
            $0.playbackQueue.setRepeat = { _ in }
        }

        await store.send(.cycleRepeatModeRequested([.off, .one]))
        await store.receive(.repeatModeChangeRequested(.off)) {
            $0.pendingRepeatChange = .init(
                requestID: UUID(0),
                target: .off
            )
        }
        await store.receive(.repeatModeChangeSucceeded(requestID: UUID(0))) {
            $0.repeatMode = .off
            $0.pendingRepeatChange = nil
        }
    }

    @Test
    func repeatCycleDoesNothingWithoutAnotherSupportedMode() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .off
        )

        await store.send(.cycleRepeatModeRequested([.off]))
    }

    @Test
    func repeatCycleDoesNothingWhileARepeatChangeIsPending() async {
        let pending = PlaybackQueueFeature.PendingRepeatChange(
            requestID: UUID(7),
            target: .all
        )
        let store = makeStore(
            repeatMode: .off,
            pendingRepeatChange: pending
        )

        await store.send(.cycleRepeatModeRequested([.off, .all, .one]))

        #expect(store.state.pendingRepeatChange == pending)
    }

    @Test
    func shuffleToggleUsesTheOppositeConfirmedMode() async {
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            shuffleMode: .songs
        ) {
            $0.playbackQueue.setShuffle = { _ in }
        }

        await store.send(.toggleShuffleRequested)
        await store.receive(.shuffleModeChangeRequested(.off)) {
            $0.pendingShuffleChange = .init(
                requestID: UUID(0),
                target: .off
            )
        }
        await store.receive(.shuffleModeChangeSucceeded(requestID: UUID(0))) {
            $0.shuffleMode = .off
            $0.pendingShuffleChange = nil
        }
    }

    @Test
    func shuffleToggleDoesNothingWhileAShuffleChangeIsPending() async {
        let pending = PlaybackQueueFeature.PendingShuffleChange(
            requestID: UUID(7),
            target: .songs
        )
        let store = makeStore(
            shuffleMode: .off,
            pendingShuffleChange: pending
        )

        await store.send(.toggleShuffleRequested)

        #expect(store.state.pendingShuffleChange == pending)
    }

    @Test
    func repeatCompletionConfirmsOnlyTheMatchingTarget() async {
        let calls = LockIsolated<[PlaybackRepeatMode]>([])
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        ) {
            $0.playbackQueue.setRepeat = { mode in
                calls.withValue { $0.append(mode) }
            }
        }

        await store.send(.repeatModeChangeRequested(.all)) {
            $0.pendingRepeatChange = .init(
                requestID: UUID(0),
                target: .all
            )
        }
        await store.receive(.repeatModeChangeSucceeded(requestID: UUID(0))) {
            $0.repeatMode = .all
            $0.pendingRepeatChange = nil
        }

        #expect(calls.value == [.all])
    }

    @Test
    func repeatAndShuffleRequestsRemainIndependent() async {
        let repeatProbe = SuspendedOperationProbe<Void>()
        let shuffleProbe = SuspendedOperationProbe<Void>()
        let tracks = makeTracks()
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id
        ) {
            $0.playbackQueue.setRepeat = { _ in
                try await repeatProbe.run()
            }
            $0.playbackQueue.setShuffle = { _ in
                try await shuffleProbe.run()
            }
        }

        await store.send(.repeatModeChangeRequested(.one)) {
            $0.pendingRepeatChange = .init(
                requestID: UUID(0),
                target: .one
            )
        }
        await repeatProbe.waitUntilStarted()
        await store.send(.shuffleModeChangeRequested(.songs)) {
            $0.pendingShuffleChange = .init(
                requestID: UUID(1),
                target: .songs
            )
        }
        await shuffleProbe.waitUntilStarted()

        #expect(store.state.pendingRepeatChange?.target == .one)
        #expect(store.state.pendingShuffleChange?.target == .songs)

        await store.send(.reset) {
            $0.tracks = []
            $0.currentTrackID = nil
            $0.repeatMode = .off
            $0.shuffleMode = .off
            $0.pendingRepeatChange = nil
            $0.pendingShuffleChange = nil
        }
        await repeatProbe.waitUntilCancelled()
        await shuffleProbe.waitUntilCancelled()
    }

    @Test
    func matchingRepeatObservationConfirmsPendingTarget() async {
        let store = makeStore(
            repeatMode: .off,
            pendingRepeatChange: .init(
                requestID: UUID(0),
                target: .one
            )
        )

        await store.send(.repeatModeObserved(.one)) {
            $0.repeatMode = .one
            $0.pendingRepeatChange = nil
        }
    }

    @Test
    func differentRepeatObservationPreservesPendingTarget() async {
        let store = makeStore(
            repeatMode: .off,
            pendingRepeatChange: .init(
                requestID: UUID(0),
                target: .one
            )
        )

        await store.send(.repeatModeObserved(.all)) {
            $0.repeatMode = .all
        }
        #expect(store.state.pendingRepeatChange?.target == .one)
    }

    @Test
    func staleRepeatResponsesCannotClearNewerRequest() async {
        let store = makeStore(
            repeatMode: .off,
            pendingRepeatChange: .init(
                requestID: UUID(1),
                target: .one
            )
        )

        await store.send(
            .repeatModeChangeSucceeded(requestID: UUID(0))
        )
        await store.send(
            .repeatModeChangeFailed(
                requestID: UUID(0),
                error: .playbackFailed
            )
        )
        #expect(store.state.pendingRepeatChange?.requestID == UUID(1))
        #expect(store.state.repeatMode == .off)
    }

    @Test
    func matchingRepeatFailurePreservesConfirmedModeAndDelegates() async {
        let store = makeStore(
            repeatMode: .all,
            pendingRepeatChange: .init(
                requestID: UUID(0),
                target: .one
            )
        )

        await store.send(
            .repeatModeChangeFailed(
                requestID: UUID(0),
                error: .playbackFailed
            )
        ) {
            $0.pendingRepeatChange = nil
        }
        await store.receive(.delegate(.modeChangeFailed(.playbackFailed)))
        #expect(store.state.repeatMode == .all)
    }

    @Test
    func matchingShuffleObservationConfirmsPendingTarget() async {
        let store = makeStore(
            shuffleMode: .off,
            pendingShuffleChange: .init(
                requestID: UUID(0),
                target: .songs
            )
        )

        await store.send(.shuffleModeObserved(.songs)) {
            $0.shuffleMode = .songs
            $0.pendingShuffleChange = nil
        }
    }

    @Test
    func differentShuffleObservationPreservesPendingTarget() async {
        let store = makeStore(
            shuffleMode: .off,
            pendingShuffleChange: .init(
                requestID: UUID(0),
                target: .songs
            )
        )

        await store.send(.shuffleModeObserved(.off))
        #expect(store.state.pendingShuffleChange?.target == .songs)
    }

    @Test
    func staleShuffleResponsesCannotClearNewerRequest() async {
        let store = makeStore(
            shuffleMode: .off,
            pendingShuffleChange: .init(
                requestID: UUID(1),
                target: .songs
            )
        )

        await store.send(
            .shuffleModeChangeSucceeded(requestID: UUID(0))
        )
        await store.send(
            .shuffleModeChangeFailed(
                requestID: UUID(0),
                error: .playbackFailed
            )
        )
        #expect(store.state.pendingShuffleChange?.requestID == UUID(1))
        #expect(store.state.shuffleMode == .off)
    }

    @Test
    func matchingShuffleFailurePreservesConfirmedModeAndDelegates() async {
        let store = makeStore(
            shuffleMode: .songs,
            pendingShuffleChange: .init(
                requestID: UUID(0),
                target: .off
            )
        )

        await store.send(
            .shuffleModeChangeFailed(
                requestID: UUID(0),
                error: .playbackFailed
            )
        ) {
            $0.pendingShuffleChange = nil
        }
        await store.receive(.delegate(.modeChangeFailed(.playbackFailed)))
        #expect(store.state.shuffleMode == .songs)
    }

    @Test
    func queueReplacementCancelsEveryQueueOperation() async {
        let queueProbe =
            SuspendedOperationProbe<PlaybackQueueNavigationResult>()
        let repeatProbe = SuspendedOperationProbe<Void>()
        let shuffleProbe = SuspendedOperationProbe<Void>()
        let tracks = makeTracks()
        let replacement = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore(
            tracks: tracks,
            currentTrackID: tracks[0].id,
            repeatMode: .all,
            shuffleMode: .songs
        ) {
            $0.playbackQueue.navigate = { _ in
                try await queueProbe.run()
            }
            $0.playbackQueue.setRepeat = { _ in
                try await repeatProbe.run()
            }
            $0.playbackQueue.setShuffle = { _ in
                try await shuffleProbe.run()
            }
        }

        await store.send(.queueTransitionRequested(.next)) {
            $0.pendingQueueTransition = .init(
                requestID: UUID(0),
                direction: .next
            )
        }
        await queueProbe.waitUntilStarted()
        await store.send(.repeatModeChangeRequested(.one)) {
            $0.pendingRepeatChange = .init(
                requestID: UUID(1),
                target: .one
            )
        }
        await repeatProbe.waitUntilStarted()
        await store.send(.shuffleModeChangeRequested(.off)) {
            $0.pendingShuffleChange = .init(
                requestID: UUID(2),
                target: .off
            )
        }
        await shuffleProbe.waitUntilStarted()

        await store.send(.replace(replacement, startingAt: tracks[0].id)) {
            $0.pendingQueueTransition = nil
            $0.pendingRepeatChange = nil
            $0.pendingShuffleChange = nil
        }

        #expect(store.state.repeatMode == .all)
        #expect(store.state.shuffleMode == .songs)
        await queueProbe.waitUntilCancelled()
        await repeatProbe.waitUntilCancelled()
        await shuffleProbe.waitUntilCancelled()
    }

    // MARK: - Helpers

    private func makeStore(
        tracks: [Track] = [],
        currentTrackID: TrackID? = nil,
        repeatMode: PlaybackRepeatMode = .off,
        shuffleMode: PlaybackShuffleMode = .off,
        pendingQueueTransition: PlaybackQueueFeature.PendingQueueTransition? = nil,
        pendingRepeatChange: PlaybackQueueFeature.PendingRepeatChange? = nil,
        pendingShuffleChange: PlaybackQueueFeature.PendingShuffleChange? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackQueueFeature> {
        TestStore(
            initialState: PlaybackQueueFeature.State(
                tracks: .init(uniqueElements: tracks),
                currentTrackID: currentTrackID,
                repeatMode: repeatMode,
                shuffleMode: shuffleMode,
                pendingQueueTransition: pendingQueueTransition,
                pendingRepeatChange: pendingRepeatChange,
                pendingShuffleChange: pendingShuffleChange
            )
        ) {
            PlaybackQueueFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            configureDependencies(&$0)
        }
    }

    private func makeTracks() -> [Track] {
        [
            makeTrack(nativeID: "1"),
            makeTrack(nativeID: "2"),
            makeTrack(nativeID: "3"),
        ]
    }

    private func makeTrack(nativeID: String) -> Track {
        Track(
            id: TrackID(providerID: "fake", nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
    }
}
