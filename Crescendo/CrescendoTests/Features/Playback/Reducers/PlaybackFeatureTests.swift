import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackFeatureTests {
    @Test
    func selectionFreezesLoadedOrderAndReplacesQueueFromTappedItem() async {
        let songs = makeSongs()
        let loadedResults = IdentifiedArray(uniqueElements: songs)
        let calls = LockIsolated<[PlaybackQueueCall]>([])
        let store = makeStore {
            $0.playbackControl.playQueue = { itemIDs, startingItemID in
                calls.withValue {
                    $0.append(
                        PlaybackQueueCall(
                            itemIDs: itemIDs,
                            startingItemID: startingItemID
                        )
                    )
                }
            }
        }

        await store.send(
            .selectionReceived(
                songs[1],
                loadedResults: loadedResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: loadedResults,
                    startingItemID: songs[1].id
                )
            )
            $0.playbackEligibility = .eligible
            $0.failure = nil
        }
        await store.receive(
            .performQueueReplacement(
                requestID: UUID(0),
                itemIDs: Array(loadedResults.ids),
                startingItemID: songs[1].id
            )
        )
        await store.receive(.queueReplacementSucceeded(requestID: UUID(0))) {
            $0.pendingOperation = nil
            $0.status = .playing
        }
        await store.receive(
            .queue(.replace(loadedResults, startingAt: songs[1].id))
        ) {
            $0.queue.songs = loadedResults
            $0.queue.currentItemID = songs[1].id
        }
        await store.receive(.timeline(.reset))

        #expect(
            calls.value
                == [
                    PlaybackQueueCall(
                        itemIDs: Array(loadedResults.ids),
                        startingItemID: songs[1].id
                    )
                ]
        )
    }

    @Test
    func pendingSelectionDoesNotReplaceConfirmedQueue() async {
        let confirmedSongs = makeSongs(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeSongs(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let probe = SuspendedQueueReplacementProbe()
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                songs: confirmedQueue,
                currentItemID: confirmedSongs[0].id
            ),
            status: .playing
        ) {
            $0.playbackControl.playQueue = probe.callAsFunction
        }

        await store.send(
            .selectionReceived(
                nextSongs[1],
                loadedResults: nextResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: nextResults,
                    startingItemID: nextSongs[1].id
                )
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .performQueueReplacement(
                requestID: UUID(0),
                itemIDs: Array(nextResults.ids),
                startingItemID: nextSongs[1].id
            )
        )
        await probe.waitUntilStarted()

        #expect(store.state.queue.songs == confirmedQueue)
        #expect(store.state.queue.currentItem == confirmedSongs[0])

        await store.send(.cancelPendingOperation) {
            $0.pendingOperation = nil
        }
        probe.succeed()
        await store.finish()
    }

    @Test
    func newerSelectionWinsAndStaleSuccessCannotPromoteItsQueue() async {
        let firstSongs = makeSongs(prefix: "first")
        let firstQueue = IdentifiedArray(uniqueElements: firstSongs)
        let secondSongs = makeSongs(prefix: "second")
        let secondQueue = IdentifiedArray(uniqueElements: secondSongs)
        let store = makeStore {
            $0.playbackControl.playQueue = { _, _ in
                try await Task.sleep(for: .seconds(60))
            }
        }

        await store.send(
            .selectionReceived(
                firstSongs[0],
                loadedResults: firstQueue,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: firstQueue,
                    startingItemID: firstSongs[0].id
                )
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .performQueueReplacement(
                requestID: UUID(0),
                itemIDs: Array(firstQueue.ids),
                startingItemID: firstSongs[0].id
            )
        )
        await store.send(
            .selectionReceived(
                secondSongs[1],
                loadedResults: secondQueue,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(1),
                    songs: secondQueue,
                    startingItemID: secondSongs[1].id
                )
            )
        }
        await store.receive(
            .performQueueReplacement(
                requestID: UUID(1),
                itemIDs: Array(secondQueue.ids),
                startingItemID: secondSongs[1].id
            )
        )
        await store.send(.queueReplacementSucceeded(requestID: UUID(0)))
        await store.send(.queueReplacementSucceeded(requestID: UUID(1))) {
            $0.pendingOperation = nil
            $0.status = .playing
        }
        await store.receive(
            .queue(.replace(secondQueue, startingAt: secondSongs[1].id))
        ) {
            $0.queue.songs = secondQueue
            $0.queue.currentItemID = secondSongs[1].id
        }
        await store.receive(.timeline(.reset))
        await store.send(.cancelPendingOperation)
    }

    @Test
    func failedReplacementPreservesConfirmedPlaybackTruth() async {
        let songs = makeSongs(prefix: "confirmed")
        let queue = IdentifiedArray(uniqueElements: songs)
        let replacementSongs = makeSongs(prefix: "replacement")
        let replacementQueue = IdentifiedArray(uniqueElements: replacementSongs)
        let timeline = PlaybackTimelineFeature.State(
            confirmedPosition: 42,
            interaction: .dragging(position: 50)
        )
        let store = makeStore(
            queue: .init(songs: queue, currentItemID: songs[1].id),
            status: .paused,
            failure: .network,
            timeline: timeline,
            pendingOperation: .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: replacementQueue,
                    startingItemID: replacementSongs[0].id
                )
            )
        )

        await store.send(
            .queueReplacementFailed(
                requestID: UUID(0),
                error: .playbackFailed
            )
        ) {
            $0.pendingOperation = nil
            $0.failure = .playbackFailed
        }

        #expect(store.state.queue == .init(songs: queue, currentItemID: songs[1].id))
        #expect(store.state.status == .paused)
        #expect(store.state.timeline == timeline)
    }

    @Test
    func invalidSelectionsNeverCallQueueReplacement() async {
        let calls = LockIsolated(0)
        let songs = makeSongs()
        let queue = IdentifiedArray(uniqueElements: songs)
        let anotherProviderSongs = [
            songs[0],
            makeSong(providerID: "other", nativeID: "other"),
        ]
        let store = makeStore {
            $0.playbackControl.playQueue = { _, _ in
                calls.withValue { $0 += 1 }
            }
        }

        await store.send(
            .selectionReceived(
                makeSong(nativeID: "missing"),
                loadedResults: queue,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )
        await store.send(
            .selectionReceived(
                songs[0],
                loadedResults: IdentifiedArray(uniqueElements: anotherProviderSongs),
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )
        await store.send(
            .selectionReceived(
                songs[0],
                loadedResults: queue,
                providerID: "other",
                playbackEligibility: .eligible
            )
        )
        await store.send(
            .selectionReceived(
                songs[0],
                loadedResults: queue,
                providerID: providerID,
                playbackEligibility: .ineligible
            )
        ) {
            $0.playbackEligibility = .ineligible
            $0.failure = nil
        }

        let unsupportedStore = makeStore(
            capabilities: MusicProviderCapabilities(
                supportsCatalogSearch: true,
                supportsEmbeddedPlayback: true,
                supportsSeeking: true,
                supportsQueueReplacement: false
            )
        ) {
            $0.playbackControl.playQueue = { _, _ in
                calls.withValue { $0 += 1 }
            }
        }
        await unsupportedStore.send(
            .selectionReceived(
                songs[0],
                loadedResults: queue,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )

        #expect(calls.value == 0)
    }

    @Test
    func unknownSnapshotItemDoesNotReplaceConfirmedMetadata() async {
        let songs = makeSongs()
        let queue = IdentifiedArray(uniqueElements: songs)
        let unknownID = MusicItemID(providerID: providerID, nativeID: "unknown")
        let snapshot = makeSnapshot(
            itemID: unknownID,
            status: .playing,
            currentTime: 12
        )
        let store = makeStore(
            queue: .init(songs: queue, currentItemID: songs[0].id)
        )

        await store.send(.snapshotReceived(snapshot)) {
            $0.status = .playing
        }
        await store.receive(.queue(.currentItemObserved(unknownID)))
        await store.receive(.timeline(.positionObserved(12))) {
            $0.timeline.confirmedPosition = 12
        }

        #expect(store.state.queue.currentItem == songs[0])
    }

    @Test
    func matchingPlayingSnapshotConfirmsPendingQueueBeforeStaleResponse() async {
        let songs = makeSongs()
        let queue = IdentifiedArray(uniqueElements: songs)
        let pending = PlaybackFeature.PendingQueueReplacement(
            requestID: UUID(0),
            songs: queue,
            startingItemID: songs[1].id
        )
        let snapshot = makeSnapshot(
            itemID: songs[1].id,
            status: .playing,
            currentTime: 7
        )
        let store = makeStore(
            pendingOperation: .queueReplacement(pending)
        )

        await store.send(.snapshotReceived(snapshot)) {
            $0.pendingOperation = nil
            $0.status = .playing
            $0.failure = nil
        }
        await store.receive(
            .queue(.replace(queue, startingAt: songs[1].id))
        ) {
            $0.queue.songs = queue
            $0.queue.currentItemID = songs[1].id
        }
        await store.receive(.timeline(.reset))
        await store.receive(.timeline(.positionObserved(7))) {
            $0.timeline.confirmedPosition = 7
        }
        await store.send(.queueReplacementSucceeded(requestID: UUID(0)))

        #expect(store.state.queue.currentItem == songs[1])
    }

    // MARK: - Helpers

    private let providerID = ProviderID(rawValue: "fake")

    private func makeStore(
        queue: PlaybackQueueFeature.State = .init(
            songs: [],
            currentItemID: nil
        ),
        status: PlaybackStatus = .idle,
        failure: MusicProviderError? = nil,
        playbackEligibility: CatalogPlaybackEligibility = .unknown,
        capabilities: MusicProviderCapabilities = .allEnabled,
        timeline: PlaybackTimelineFeature.State = .init(
            confirmedPosition: 0,
            interaction: .idle
        ),
        pendingOperation: PlaybackFeature.PendingOperation? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackFeature> {
        TestStore(
            initialState: PlaybackFeature.State(
                providerID: providerID,
                queue: queue,
                status: status,
                failure: failure,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities,
                timeline: timeline,
                pendingOperation: pendingOperation
            )
        ) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            configureDependencies(&$0)
        }
    }

    private func makeSongs(prefix: String = "song") -> [SongSummary] {
        [
            makeSong(nativeID: "\(prefix)-1"),
            makeSong(nativeID: "\(prefix)-2"),
            makeSong(nativeID: "\(prefix)-3"),
        ]
    }

    private func makeSong(
        providerID: ProviderID = "fake",
        nativeID: String
    ) -> SongSummary {
        SongSummary(
            id: MusicItemID(providerID: providerID, nativeID: nativeID),
            title: nativeID,
            artistName: "Artist",
            artworkURL: nil,
            duration: 180
        )
    }

    private func makeSnapshot(
        itemID: MusicItemID?,
        status: PlaybackStatus,
        currentTime: TimeInterval
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            currentItemID: itemID,
            status: status,
            currentTime: currentTime,
            playbackRate: .normal,
            repeatMode: .off,
            shuffleMode: .off
        )
    }
}

private struct PlaybackQueueCall: Equatable {
    let itemIDs: [MusicItemID]
    let startingItemID: MusicItemID
}

private struct SuspendedQueueReplacementProbe: Sendable {
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let pendingContinuation =
        LockIsolated<CheckedContinuation<Void, any Error>?>(nil)

    init() {
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
    }

    func callAsFunction(
        _ itemIDs: [MusicItemID],
        _ startingItemID: MusicItemID
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pendingContinuation.withValue { $0 = continuation }
            startedContinuation.yield()
        }
    }

    func waitUntilStarted() async {
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        startedContinuation.finish()
    }

    func succeed() {
        pendingContinuation.withValue { pendingContinuation in
            let continuation = pendingContinuation
            pendingContinuation = nil
            continuation?.resume(returning: ())
        }
    }
}
