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
            pendingQueueTransition: nil
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
            pendingQueueTransition: nil
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
            pendingQueueTransition: .init(
                requestID: UUID(0),
                direction: .next
            )
        )

        await store.send(.reset) {
            $0.songs = []
            $0.currentItemID = nil
            $0.pendingQueueTransition = nil
        }

        #expect(store.state.currentItem == nil)
    }

    @Test(arguments: [
        PlaybackQueueFeature.QueueTransitionDirection.previous,
        .next,
    ])
    func queueTransitionCallsOnlyTheRequestedCapabilityAndWaitsForObservation(
        direction: PlaybackQueueFeature.QueueTransitionDirection
    ) async {
        let songs = makeSongs()
        let calls = LockIsolated<[PlaybackQueueFeature.QueueTransitionDirection]>([])
        let store = makeStore(
            songs: songs,
            currentItemID: songs[1].id
        ) {
            $0.playbackQueue.previous = {
                calls.withValue { $0.append(.previous) }
            }
            $0.playbackQueue.next = {
                calls.withValue { $0.append(.next) }
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
            $0.playbackQueue.previous = {
                calls.withValue { $0 += 1 }
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
            $0.playbackQueue.next = {
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
    func resetCancelsAnExecutingQueueTransition() async {
        let songs = makeSongs()
        let probe = SuspendedQueueTransitionProbe()
        let store = makeStore(
            songs: songs,
            currentItemID: songs[0].id
        ) {
            $0.playbackQueue.next = probe.callAsFunction
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

    // MARK: - Helpers

    private func makeStore(
        songs: [SongSummary] = [],
        currentItemID: MusicItemID? = nil,
        pendingQueueTransition: PlaybackQueueFeature.PendingQueueTransition? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackQueueFeature> {
        TestStore(
            initialState: PlaybackQueueFeature.State(
                songs: .init(uniqueElements: songs),
                currentItemID: currentItemID,
                pendingQueueTransition: pendingQueueTransition
            )
        ) {
            PlaybackQueueFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            configureDependencies(&$0)
        }
    }

    private struct SuspendedQueueTransitionProbe: Sendable {
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
