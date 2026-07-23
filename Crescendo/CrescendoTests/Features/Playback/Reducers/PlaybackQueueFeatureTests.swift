import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackQueueFeatureTests {
    @Test
    func replacementStoresTheFrozenOrderAndStartingItem() async {
        let songs = makeSongs()
        let queue = IdentifiedArray(uniqueElements: songs)
        let store = makeStore()

        await store.send(.replace(queue, startingAt: songs[1].id)) {
            $0.songs = queue
            $0.currentItemID = songs[1].id
        }

        #expect(store.state.currentItem == songs[1])
    }

    @Test
    func observedQueueItemUpdatesTheCurrentIdentity() async {
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
        )

        await store.send(.currentItemObserved(songs[1].id)) {
            $0.currentItemID = songs[1].id
        }

        #expect(store.state.currentItem == songs[1])
    }

    @Test(arguments: [
        MusicItemID(providerID: "fake", nativeID: "unknown"),
        MusicItemID(providerID: "other", nativeID: "1"),
    ])
    func unknownObservedItemPreservesTheCurrentItem(
        observedItemID: MusicItemID
    ) async {
        let songs = makeSongs()
        let state = PlaybackQueueFeature.State(
            songs: .init(uniqueElements: songs),
            currentItemID: songs[0].id,
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
        #expect(store.state.currentItem == songs[0])
    }

    @Test
    func missingObservedItemPreservesTheCurrentItem() async {
        let songs = makeSongs()
        let state = PlaybackQueueFeature.State(
            songs: .init(uniqueElements: songs),
            currentItemID: songs[0].id,
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
        #expect(store.state.currentItem == songs[0])
    }

    @Test
    func resetEmptiesTheQueueAndCurrentIdentity() async {
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
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
            $0.songs = []
            $0.currentItemID = nil
            $0.repeatMode = .off
            $0.shuffleMode = .off
            $0.pendingQueueTransition = nil
            $0.pendingRepeatChange = nil
            $0.pendingShuffleChange = nil
        }

        #expect(store.state.currentItem == nil)
    }

    @Test(arguments: [
        PlaybackQueueNavigationDirection.previous,
        .next,
    ])
    func queueTransitionCallsOnlyTheRequestedCapabilityAndWaitsForObservation(
        direction: PlaybackQueueNavigationDirection
    ) async {
        let songs = makeSongs()
        let calls = LockIsolated<[PlaybackQueueNavigationDirection]>([])
        let store = makeStore(
            songs: songs,
            currentItemID: songs[1].id
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
        #expect(store.state.currentItemID == songs[1].id)
        #expect(store.state.pendingQueueTransition != nil)
    }

    @Test
    func observedChangedItemConfirmsThePendingQueueTransition() async {
        let songs = makeSongs()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(0),
            direction: .next
        )
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
            pendingQueueTransition: pending
        )

        await store.send(.currentItemObserved(songs[1].id)) {
            $0.currentItemID = songs[1].id
            $0.pendingQueueTransition = nil
        }
    }

    @Test
    func unchangedOrUnknownObservationDoesNotConfirmAQueueTransition() async {
        let songs = makeSongs()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(7),
            direction: .next
        )
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
            pendingQueueTransition: pending
        )

        await store.send(.currentItemObserved(songs[0].id))
        await store.send(
            .currentItemObserved(
                MusicItemID(providerID: "fake", nativeID: "unknown")
            )
        )

        #expect(store.state.currentItemID == songs[0].id)
        #expect(store.state.pendingQueueTransition == pending)
    }

    @Test
    func unresolvedQueueTransitionRejectsAnotherRequest() async {
        let songs = makeSongs()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(7),
            direction: .next
        )
        let calls = LockIsolated(0)
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
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
        let songs = makeSongs()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(1),
            direction: .next
        )
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
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
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
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

        #expect(store.state.currentItemID == songs[0].id)
    }

    @Test
    func queueBoundaryClearsTheOperationWithoutDelegatingFailure() async {
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
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

        #expect(store.state.currentItemID == songs[0].id)
    }

    @Test
    func resetCancelsAnExecutingQueueTransition() async {
        let songs = makeSongs()
        let probe =
            SuspendedOperationProbe<PlaybackQueueNavigationResult>()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
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
            $0.songs = []
            $0.currentItemID = nil
            $0.pendingQueueTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func repeatCycleSelectsTheNextSupportedMode() async {
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
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
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
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
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
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
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
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
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
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
        let songs = makeSongs()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
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
            $0.songs = []
            $0.currentItemID = nil
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
        let songs = makeSongs()
        let replacement = IdentifiedArray(uniqueElements: songs)
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id,
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

        await store.send(.replace(replacement, startingAt: songs[0].id)) {
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
        songs: [SongSummary] = [],
        currentItemID: MusicItemID? = nil,
        repeatMode: PlaybackRepeatMode = .off,
        shuffleMode: PlaybackShuffleMode = .off,
        pendingQueueTransition: PlaybackQueueFeature.PendingQueueTransition? = nil,
        pendingRepeatChange: PlaybackQueueFeature.PendingRepeatChange? = nil,
        pendingShuffleChange: PlaybackQueueFeature.PendingShuffleChange? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackQueueFeature> {
        TestStore(
            initialState: PlaybackQueueFeature.State(
                songs: .init(uniqueElements: songs),
                currentItemID: currentItemID,
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

    private func makeSongs() -> [SongSummary] {
        [
            makeSong(nativeID: "1"),
            makeSong(nativeID: "2"),
            makeSong(nativeID: "3"),
        ]
    }

    private func makeSong(nativeID: String) -> SongSummary {
        SongSummary(
            id: MusicItemID(providerID: "fake", nativeID: nativeID),
            title: "Song \(nativeID)",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
