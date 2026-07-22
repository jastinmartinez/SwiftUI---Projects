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
            $0.playbackQueue.replace = { itemIDs, startingItemID in
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
            $0.isPlayerPresented = true
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
            $0.playbackQueue.replace = probe.callAsFunction
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
            $0.playbackQueue.replace = { _, _ in
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
            $0.isPlayerPresented = true
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
            $0.playbackQueue.replace = { _, _ in
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
            $0.isPlayerPresented = true
        }

        let unsupportedStore = makeStore(
            capabilities: MusicProviderCapabilities(
                supportsCatalogSearch: true,
                supportsEmbeddedPlayback: true,
                supportsSeeking: true,
                supportsQueueReplacement: false,
                supportsQueueTransitions: true
            )
        ) {
            $0.playbackQueue.replace = { _, _ in
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

    @Test
    func playingPlayPauseStartsPendingPauseAndCallsOnlyPause() async {
        let songs = makeSongs()
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: .playing
        ) {
            $0.playbackTransport.pause = {
                calls.withValue { $0.append("pause") }
            }
            $0.playbackTransport.play = {
                calls.withValue { $0.append("resume") }
            }
        }

        await store.send(.playPauseTapped) {
            $0.pendingOperation = .statusChange(
                .init(requestID: UUID(0), target: .paused)
            )
            $0.failure = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .paused)
        )
        await store.receive(.statusChangeSucceeded(requestID: UUID(0)))

        #expect(calls.value == ["pause"])
        #expect(store.state.status == .playing)
        #expect(
            store.state.pendingOperation
                == .statusChange(
                    .init(requestID: UUID(0), target: .paused)
                )
        )
    }

    @Test(arguments: [PlaybackStatus.paused, .stopped])
    func pausedOrStoppedPlayPauseStartsPendingPlayAndCallsOnlyResume(
        status: PlaybackStatus
    ) async {
        let songs = makeSongs()
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: status
        ) {
            $0.playbackTransport.pause = {
                calls.withValue { $0.append("pause") }
            }
            $0.playbackTransport.play = {
                calls.withValue { $0.append("resume") }
            }
        }

        await store.send(.playPauseTapped) {
            $0.pendingOperation = .statusChange(
                .init(requestID: UUID(0), target: .playing)
            )
            $0.failure = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .playing)
        )
        await store.receive(.statusChangeSucceeded(requestID: UUID(0)))

        #expect(calls.value == ["resume"])
        #expect(store.state.status == status)
        #expect(
            store.state.pendingOperation
                == .statusChange(
                    .init(requestID: UUID(0), target: .playing)
                )
        )
    }

    @Test
    func playPauseIsIgnoredWhileAParentOperationIsPending() async {
        let songs = makeSongs()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .paused
        )
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: .playing,
            pendingOperation: .statusChange(pending)
        )

        #expect(!store.state.canRequestPlayPause)
        await store.send(.playPauseTapped)
        #expect(store.state.pendingOperation == .statusChange(pending))
    }

    @Test
    func playSupersedesPendingStop() async {
        let songs = makeSongs()
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: .playing,
            pendingOperation: .statusChange(
                .init(requestID: UUID(99), target: .stopped)
            )
        ) {
            $0.playbackTransport.play = {
                calls.withValue { $0.append("resume") }
            }
        }

        #expect(store.state.canRequestPlayPause)
        await store.send(.playPauseTapped) {
            $0.pendingOperation = .statusChange(
                .init(requestID: UUID(0), target: .playing)
            )
            $0.failure = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .playing)
        )
        await store.receive(.statusChangeSucceeded(requestID: UUID(0)))

        #expect(calls.value == ["resume"])
    }

    @Test(arguments: [
        PlaybackFeature.PendingStatusChange.Target.playing,
        .paused,
        .stopped,
    ])
    func selectionSupersedesPendingStatusChange(
        target: PlaybackFeature.PendingStatusChange.Target
    ) async {
        let songs = makeSongs()
        let replacement = IdentifiedArray(uniqueElements: makeSongs(prefix: "next"))
        let statusProbe = SuspendedPlaybackOperationProbe()
        let queueProbe = SuspendedPlaybackOperationProbe()
        let status: PlaybackStatus
        switch target {
        case .playing:
            status = .paused
        case .paused, .stopped:
            status = .playing
        }
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: status
        ) {
            switch target {
            case .playing:
                $0.playbackTransport.play = statusProbe.callAsFunction
            case .paused:
                $0.playbackTransport.pause = statusProbe.callAsFunction
            case .stopped:
                $0.playbackTransport.stop = statusProbe.callAsFunction
            }
            $0.playbackQueue.replace = queueProbe.callAsFunction
        }

        await store.send(target == .stopped ? .stopTapped : .playPauseTapped) {
            $0.pendingOperation = .statusChange(
                .init(requestID: UUID(0), target: target)
            )
            $0.failure = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: target)
        )
        await statusProbe.waitUntilStarted()
        await store.send(
            .selectionReceived(
                replacement[0],
                loadedResults: replacement,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(1),
                    songs: replacement,
                    startingItemID: replacement[0].id
                )
            )
            $0.playbackEligibility = .eligible
            $0.failure = nil
        }
        await store.receive(
            .performQueueReplacement(
                requestID: UUID(1),
                itemIDs: Array(replacement.ids),
                startingItemID: replacement[0].id
            )
        )
        await statusProbe.waitUntilCancelled()
        await store.send(.cancelPendingOperation) {
            $0.pendingOperation = nil
        }
        await queueProbe.waitUntilCancelled()
    }

    @Test
    func stopSupersedesPendingQueueReplacementAndStatusChangePreventsAnotherStop() async {
        let songs = makeSongs()
        let replacement = IdentifiedArray(uniqueElements: songs)
        let queueProbe = SuspendedPlaybackOperationProbe()
        let stopProbe = SuspendedPlaybackOperationProbe()
        let store = makeStore(
            status: .playing
        ) {
            $0.playbackQueue.replace = queueProbe.callAsFunction
            $0.playbackTransport.stop = stopProbe.callAsFunction
        }

        await store.send(
            .selectionReceived(
                songs[0],
                loadedResults: replacement,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: replacement,
                    startingItemID: songs[0].id
                )
            )
            $0.playbackEligibility = .eligible
            $0.failure = nil
        }
        await store.receive(
            .performQueueReplacement(
                requestID: UUID(0),
                itemIDs: Array(replacement.ids),
                startingItemID: songs[0].id
            )
        )
        await queueProbe.waitUntilStarted()

        #expect(store.state.canRequestStop)
        await store.send(.stopTapped) {
            $0.pendingOperation = .statusChange(
                .init(requestID: UUID(1), target: .stopped)
            )
            $0.failure = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(1), target: .stopped)
        )
        await stopProbe.waitUntilStarted()
        await queueProbe.waitUntilCancelled()

        let pendingStatus = PlaybackFeature.PendingStatusChange(
            requestID: UUID(1),
            target: .stopped
        )
        #expect(!store.state.canRequestStop)
        #expect(store.state.pendingOperation == .statusChange(pendingStatus))
        await store.send(.stopTapped)
        await store.send(.cancelPendingOperation) {
            $0.pendingOperation = nil
        }
        await stopProbe.waitUntilCancelled()
    }

    @Test
    func successfulStatusCommandWaitsForMatchingSnapshot() async {
        let songs = makeSongs()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(1),
            target: .paused
        )
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: .playing,
            pendingOperation: .statusChange(pending)
        )

        await store.send(.statusChangeSucceeded(requestID: UUID(0)))
        #expect(store.state.pendingOperation == .statusChange(pending))
        await store.send(.statusChangeSucceeded(requestID: UUID(1)))
        #expect(store.state.pendingOperation == .statusChange(pending))
        #expect(store.state.status == .playing)

        await store.send(
            .snapshotReceived(
                makeSnapshot(
                    itemID: songs[0].id,
                    status: .paused,
                    currentTime: 12
                )
            )
        ) {
            $0.pendingOperation = nil
            $0.status = .paused
            $0.failure = nil
        }
        await store.receive(.queue(.currentItemObserved(songs[0].id)))
        await store.receive(.timeline(.positionObserved(12))) {
            $0.timeline.confirmedPosition = 12
        }
    }

    @Test
    func snapshotsKeepProviderTruthUntilTheyMatchPendingTarget() async {
        let songs = makeSongs()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .stopped
        )
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: .playing,
            timeline: .init(confirmedPosition: 4, interaction: .idle),
            pendingOperation: .statusChange(pending)
        )

        await store.send(
            .snapshotReceived(
                makeSnapshot(
                    itemID: songs[0].id,
                    status: .paused,
                    currentTime: 7
                )
            )
        ) {
            $0.status = .paused
        }
        await store.receive(.queue(.currentItemObserved(songs[0].id)))
        await store.receive(.timeline(.positionObserved(7))) {
            $0.timeline.confirmedPosition = 7
        }
        #expect(store.state.pendingOperation == .statusChange(pending))
        #expect(store.state.status == .paused)
        #expect(store.state.timeline.confirmedPosition == 7)
    }

    @Test
    func stoppedSnapshotConfirmationResetsTimelineWithoutApplyingSnapshotPosition() async {
        let songs = makeSongs()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .stopped
        )
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: .playing,
            timeline: .init(confirmedPosition: 42, interaction: .dragging(position: 50)),
            pendingOperation: .statusChange(pending)
        )

        await store.send(
            .snapshotReceived(
                makeSnapshot(
                    itemID: songs[0].id,
                    status: .stopped,
                    currentTime: 9
                )
            )
        ) {
            $0.status = .stopped
            $0.pendingOperation = nil
            $0.failure = nil
        }
        await store.receive(.timeline(.reset)) {
            $0.timeline.confirmedPosition = 0
            $0.timeline.interaction = .idle
        }
        await store.receive(.queue(.currentItemObserved(songs[0].id)))

        #expect(store.state.timeline.confirmedPosition == 0)
    }

    @Test
    func failedStatusChangeClearsOnlyMatchingRequestAndPreservesConfirmedTruth() async {
        let songs = makeSongs()
        let timeline = PlaybackTimelineFeature.State(
            confirmedPosition: 42,
            interaction: .dragging(position: 50)
        )
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(1),
            target: .stopped
        )
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: .paused,
            timeline: timeline,
            pendingOperation: .statusChange(pending)
        )

        await store.send(.statusChangeFailed(requestID: UUID(0), error: .network))
        #expect(store.state.pendingOperation == .statusChange(pending))
        await store.send(.statusChangeFailed(requestID: UUID(1), error: .playbackFailed)) {
            $0.pendingOperation = nil
            $0.failure = .playbackFailed
        }

        #expect(store.state.status == .paused)
        #expect(store.state.timeline == timeline)
    }

    @Test
    func timelineResetsOnlyAfterStoppedIsConfirmed() async {
        let songs = makeSongs()
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id
            ),
            status: .playing,
            timeline: .init(
                confirmedPosition: 42,
                interaction: .dragging(position: 50)
            )
        ) {
            $0.playbackTransport.stop = {}
        }

        await store.send(.stopTapped) {
            $0.pendingOperation = .statusChange(
                .init(requestID: UUID(0), target: .stopped)
            )
            $0.failure = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .stopped)
        )
        #expect(store.state.timeline.confirmedPosition == 42)
        await store.receive(.statusChangeSucceeded(requestID: UUID(0)))
        #expect(store.state.status == .playing)
        #expect(store.state.timeline.confirmedPosition == 42)

        await store.send(
            .snapshotReceived(
                makeSnapshot(
                    itemID: songs[0].id,
                    status: .stopped,
                    currentTime: 0
                )
            )
        ) {
            $0.pendingOperation = nil
            $0.status = .stopped
            $0.failure = nil
        }
        await store.receive(.timeline(.reset)) {
            $0.timeline.confirmedPosition = 0
            $0.timeline.interaction = .idle
        }
        await store.receive(.queue(.currentItemObserved(songs[0].id)))
    }

    @Test
    func statusPermissionsMatchReducerPolicy() {
        let songs = IdentifiedArray(uniqueElements: makeSongs())
        let active = PlaybackFeature.State(
            providerID: providerID,
            queue: .init(songs: songs, currentItemID: songs[0].id),
            status: .playing,
            failure: nil,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: .init(confirmedPosition: 0, interaction: .idle),
            pendingOperation: nil,
            pendingReset: nil,
            isPlayerPresented: false
        )
        let replacing = PlaybackFeature.State(
            providerID: providerID,
            queue: .init(songs: [], currentItemID: nil),
            status: .stopped,
            failure: nil,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: .init(confirmedPosition: 0, interaction: .idle),
            pendingOperation: .queueReplacement(
                .init(requestID: UUID(0), songs: songs, startingItemID: songs[0].id)
            ),
            pendingReset: nil,
            isPlayerPresented: false
        )

        #expect(active.canRequestPlayPause)
        #expect(active.canRequestStop)
        #expect(!replacing.canRequestPlayPause)
        #expect(replacing.canRequestStop)
    }

    @Test
    func oldProviderSnapshotIsIgnoredDuringResetWindow() async {
        let pendingReset = PlaybackFeature.PendingReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(pendingReset: pendingReset)
        let staleSnapshot = PlaybackSnapshot(
            currentItemID: nil,
            status: .playing,
            currentTime: 99,
            playbackRate: .normal,
            repeatMode: .off,
            shuffleMode: .off
        )

        await store.send(.snapshotReceived(staleSnapshot))

        #expect(store.state.status == .idle)
        #expect(store.state.timeline.confirmedPosition == 0)
        #expect(store.state.pendingReset == pendingReset)
    }

    @Test
    func staleApplyResetCannotFinalizeRepeatedProviderReset() async {
        let pendingReset = PlaybackFeature.PendingReset(
            requestID: UUID(1),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(pendingReset: pendingReset)

        await store.send(.applyReset(requestID: UUID(0)))

        #expect(store.state.pendingReset == pendingReset)
        #expect(store.state.providerID == providerID)
    }

    @Test
    func resetWindowRejectsNewParentOperations() async {
        let songs = IdentifiedArray(uniqueElements: makeSongs())
        let pendingReset = PlaybackFeature.PendingReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(
            queue: .init(songs: songs, currentItemID: songs[0].id),
            status: .playing,
            pendingReset: pendingReset
        )

        #expect(!store.state.canRequestPlayPause)
        #expect(!store.state.canRequestStop)
        await store.send(
            .selectionReceived(
                songs[1],
                loadedResults: songs,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )

        #expect(store.state.pendingOperation == nil)
        #expect(store.state.pendingReset == pendingReset)
    }

    @Test
    func resetWindowRejectsQueuedPlaybackEffects() async {
        let songs = IdentifiedArray(uniqueElements: makeSongs())
        let pendingOperation = PlaybackFeature.PendingOperation.statusChange(
            .init(requestID: UUID(1), target: .paused)
        )
        let pendingReset = PlaybackFeature.PendingReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let calls = LockIsolated(0)
        let store = makeStore(
            queue: .init(songs: songs, currentItemID: songs[0].id),
            status: .playing,
            pendingOperation: pendingOperation,
            pendingReset: pendingReset
        ) {
            $0.playbackTransport.pause = {
                calls.withValue { $0 += 1 }
            }
        }

        await store.send(
            .performStatusChange(
                requestID: UUID(1),
                target: .paused
            )
        )
        await Task.yield()

        #expect(calls.value == 0)
        #expect(store.state.pendingOperation == pendingOperation)
        #expect(store.state.pendingReset == pendingReset)
    }

    @Test
    func resetWindowRejectsIneligibleSelectionPresentation() async {
        let songs = IdentifiedArray(uniqueElements: makeSongs())
        let pendingReset = PlaybackFeature.PendingReset(
            requestID: UUID(0),
            providerID: providerID,
            capabilities: .allEnabled
        )
        let store = makeStore(pendingReset: pendingReset)

        await store.send(
            .selectionReceived(
                songs[0],
                loadedResults: songs,
                providerID: providerID,
                playbackEligibility: .ineligible
            )
        )

        #expect(store.state.playbackEligibility == .unknown)
        #expect(!store.state.isPlayerPresented)
        #expect(store.state.pendingReset == pendingReset)
    }

    @Test
    func continuousTimelineIntentIsClampedByTheParent() async {
        let store = makeStore(queue: makeQueue(duration: 180))

        await store.send(.timelinePositionChanged(200))
        await store.receive(.timeline(.positionChanged(180))) {
            $0.timeline.interaction = .dragging(position: 180)
        }
    }

    @Test
    func timelineInteractionEndClampsTheParentDraftBeforeSeeking() async {
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let store = makeStore(
            queue: makeQueue(duration: 180),
            timeline: .init(
                confirmedPosition: 40,
                interaction: .dragging(position: 300)
            )
        ) {
            $0.playbackTimeline.seek = { position in
                seekPositions.withValue { $0.append(position) }
            }
        }

        await store.send(.timelineInteractionEnded)
        await store.receive(.timeline(.positionChanged(180))) {
            $0.timeline.interaction = .dragging(position: 180)
        }
        await store.receive(.timeline(.dragEnded))
        await store.receive(.timeline(.seekRequested(180))) {
            $0.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 180
            )
        }
        await store.receive(.timeline(.seekSucceeded(requestID: UUID(0)))) {
            $0.timeline.confirmedPosition = 180
            $0.timeline.interaction = .idle
        }

        #expect(seekPositions.value == [180])
    }

    @Test
    func newerDiscreteParentSeekSupersedesAnInFlightProviderSeek() async {
        let firstSeek = SuspendedSeekProbe()
        let replacementSeek = SuspendedSeekProbe()
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let store = makeStore(
            queue: makeQueue(duration: 180),
            timeline: .init(
                confirmedPosition: 40,
                interaction: .dragging(position: 30)
            )
        ) {
            $0.playbackTimeline.seek = { position in
                seekPositions.withValue { $0.append(position) }
                if position == 30 {
                    try await firstSeek(position)
                } else {
                    try await replacementSeek(position)
                }
            }
        }

        await store.send(.timelineInteractionEnded)
        await store.receive(.timeline(.dragEnded))
        await store.receive(.timeline(.seekRequested(30))) {
            $0.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 30
            )
        }
        await firstSeek.waitUntilStarted()

        await store.send(.seekForwardTapped)
        await store.receive(.timeline(.seekRequested(45))) {
            $0.timeline.interaction = .seeking(
                requestID: UUID(1),
                position: 45
            )
        }
        #expect(firstSeek.cancellationObserved.value)
        await replacementSeek.waitUntilStarted()
        #expect(!replacementSeek.cancellationObserved.value)

        firstSeek.succeed()
        await store.send(.timeline(.seekSucceeded(requestID: UUID(0))))
        #expect(
            store.state.timeline.interaction
                == .seeking(requestID: UUID(1), position: 45)
        )

        replacementSeek.succeed()
        await store.receive(.timeline(.seekSucceeded(requestID: UUID(1)))) {
            $0.timeline.confirmedPosition = 45
            $0.timeline.interaction = .idle
        }

        #expect(seekPositions.value == [30, 45])
    }

    @Test
    func backwardSeekClampsAnOutOfRangeInteractionPositionToDuration() async {
        let store = makeStore(
            queue: makeQueue(duration: 180),
            timeline: .init(
                confirmedPosition: 40,
                interaction: .dragging(position: 300)
            )
        ) {
            $0.playbackTimeline.seek = { _ in }
        }

        await store.send(.seekBackwardTapped)
        await store.receive(.timeline(.seekRequested(180))) {
            $0.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 180
            )
        }
        await store.receive(.timeline(.seekSucceeded(requestID: UUID(0)))) {
            $0.timeline.confirmedPosition = 180
            $0.timeline.interaction = .idle
        }
    }

    @Test
    func restartAndForwardSeekClampToTimelineBounds() async {
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let store = makeStore(
            queue: makeQueue(duration: 180),
            timeline: .init(confirmedPosition: 175, interaction: .idle)
        ) {
            $0.playbackTimeline.seek = { position in
                seekPositions.withValue { $0.append(position) }
            }
        }

        await store.send(.seekForwardTapped)
        await store.receive(.timeline(.seekRequested(180))) {
            $0.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 180
            )
        }
        await store.receive(.timeline(.seekSucceeded(requestID: UUID(0)))) {
            $0.timeline.confirmedPosition = 180
            $0.timeline.interaction = .idle
        }

        await store.send(.restartTapped)
        await store.receive(.timeline(.seekRequested(0))) {
            $0.timeline.interaction = .seeking(
                requestID: UUID(1),
                position: 0
            )
        }
        await store.receive(.timeline(.seekSucceeded(requestID: UUID(1)))) {
            $0.timeline.confirmedPosition = 0
            $0.timeline.interaction = .idle
        }

        #expect(seekPositions.value == [180, 0])
    }

    @Test
    func unavailableTimelineIntentIsATrueNoOp() async {
        var capabilities = MusicProviderCapabilities.allEnabled
        capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: capabilities.supportsCatalogSearch,
            supportsEmbeddedPlayback: capabilities.supportsEmbeddedPlayback,
            supportsSeeking: false,
            supportsQueueReplacement: capabilities.supportsQueueReplacement,
            supportsQueueTransitions: capabilities.supportsQueueTransitions
        )
        let store = makeStore(
            queue: makeQueue(duration: 180),
            capabilities: capabilities
        )

        await store.send(.timelinePositionChanged(30))
        await store.send(.timelineInteractionEnded)
        await store.send(.restartTapped)
        await store.send(.seekBackwardTapped)
        await store.send(.seekForwardTapped)
    }

    @Test
    func missingDurationTimelineIntentsAreTrueNoOps() async {
        let store = makeStore(queue: makeQueue(duration: nil))

        await store.send(.timelinePositionChanged(30))
        await store.send(.timelineInteractionEnded)
        await store.send(.restartTapped)
        await store.send(.seekBackwardTapped)
        await store.send(.seekForwardTapped)
    }

    @Test
    func nonpositiveDurationTimelineIntentsAreTrueNoOps() async {
        let store = makeStore(queue: makeQueue(duration: 0))

        await store.send(.timelinePositionChanged(30))
        await store.send(.timelineInteractionEnded)
        await store.send(.restartTapped)
        await store.send(.seekBackwardTapped)
        await store.send(.seekForwardTapped)
    }

    @Test
    func resetWindowTimelineIntentsAreTrueNoOps() async {
        let pendingReset = PlaybackFeature.PendingReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(
            queue: makeQueue(duration: 180),
            pendingReset: pendingReset
        )

        await store.send(.timelinePositionChanged(30))
        await store.send(.timelineInteractionEnded)
        await store.send(.restartTapped)
        await store.send(.seekBackwardTapped)
        await store.send(.seekForwardTapped)
    }

    // MARK: - Helpers

    private let providerID = ProviderID(rawValue: "fake")

    private func makeQueue(duration: TimeInterval?) -> PlaybackQueueFeature.State {
        let song = SongSummary(
            id: MusicItemID(providerID: providerID, nativeID: "timeline"),
            title: "Timeline",
            artistName: "Artist",
            artworkURL: nil,
            duration: duration
        )
        return PlaybackQueueFeature.State(
            songs: IdentifiedArray(uniqueElements: [song]),
            currentItemID: song.id
        )
    }

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
        pendingReset: PlaybackFeature.PendingReset? = nil,
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
                pendingOperation: pendingOperation,
                pendingReset: pendingReset,
                isPlayerPresented: false
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

private struct SuspendedPlaybackOperationProbe: Sendable {
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

    func callAsFunction(
        _ itemIDs: [MusicItemID],
        _ startingItemID: MusicItemID
    ) async throws {
        try await suspend()
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
}
