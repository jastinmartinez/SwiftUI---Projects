import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackFeatureTests {
    @Test
    func repeatTapCyclesOnlyThroughSupportedModes() async {
        let song = makeSong(nativeID: "song")
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: true,
            supportsQueueTransitions: true,
            supportedRepeatModes: [.off, .one],
            supportsShuffle: true
        )
        let queue = PlaybackQueueFeature.State(
            songs: .init(uniqueElements: [song]),
            currentItemID: song.id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
        let store = makeStore(
            queue: queue,
            capabilities: capabilities
        ) {
            $0.playbackQueue.setRepeat = { _ in }
        }

        await store.send(.repeatTapped)
        await store.receive(
            .queue(.cycleRepeatModeRequested([.off, .one]))
        )
        await store.receive(.queue(.repeatModeChangeRequested(.one))) {
            $0.queue.pendingRepeatChange = .init(
                requestID: UUID(0),
                target: .one
            )
        }
        await store.receive(
            .queue(.repeatModeChangeSucceeded(requestID: UUID(0)))
        ) {
            $0.queue.repeatMode = .one
            $0.queue.pendingRepeatChange = nil
        }
    }

    @Test
    func shuffleTapRoutesTargetSelectionToTheQueueChild() async {
        let song = makeSong(nativeID: "song")
        let queue = PlaybackQueueFeature.State(
            songs: .init(uniqueElements: [song]),
            currentItemID: song.id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
        let store = makeStore(queue: queue) {
            $0.playbackQueue.setShuffle = { _ in }
        }

        await store.send(.shuffleTapped)
        await store.receive(.queue(.toggleShuffleRequested))
        await store.receive(.queue(.shuffleModeChangeRequested(.songs))) {
            $0.queue.pendingShuffleChange = .init(
                requestID: UUID(0),
                target: .songs
            )
        }
        await store.receive(
            .queue(.shuffleModeChangeSucceeded(requestID: UUID(0)))
        ) {
            $0.queue.shuffleMode = .songs
            $0.queue.pendingShuffleChange = nil
        }
    }

    @Test
    func repeatRequestLeavesIndependentCommandsAuthorized() async {
        let song = makeSong(nativeID: "song")
        let repeatProbe = SuspendedOperationProbe<Void>()
        let queue = PlaybackQueueFeature.State(
            songs: .init(uniqueElements: [song]),
            currentItemID: song.id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
        let store = makeStore(queue: queue) {
            $0.playbackQueue.setRepeat = { _ in
                try await repeatProbe.run()
            }
        }

        await store.send(.repeatTapped)
        await store.receive(
            .queue(.cycleRepeatModeRequested([.off, .all, .one]))
        )
        await store.receive(.queue(.repeatModeChangeRequested(.all))) {
            $0.queue.pendingRepeatChange = .init(
                requestID: UUID(0),
                target: .all
            )
        }
        await repeatProbe.waitUntilStarted()

        #expect(!store.state.commandPolicy.allows(.repeatMode))
        #expect(store.state.commandPolicy.allows(.shuffleMode))
        #expect(store.state.commandPolicy.allows(.next))
        #expect(store.state.commandPolicy.allows(.seek))

        repeatProbe.succeed()
        await store.receive(
            .queue(.repeatModeChangeSucceeded(requestID: UUID(0)))
        ) {
            $0.queue.repeatMode = .all
            $0.queue.pendingRepeatChange = nil
        }
    }

    @Test
    func snapshotRoutesConfirmedModesBeforePlaybackReconciliation() async {
        let snapshot = makeSnapshot(
            itemID: nil,
            status: .idle,
            currentTime: 0,
            repeatMode: .one,
            shuffleMode: .songs
        )
        let store = makeStore()

        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.one))) {
            $0.queue.repeatMode = .one
        }
        await store.receive(.queue(.shuffleModeObserved(.songs))) {
            $0.queue.shuffleMode = .songs
        }
        await store.receive(.reconcileSnapshot(snapshot))
        await store.receive(.queue(.currentItemObserved(nil)))
        await store.receive(.timeline(.positionObserved(0)))
    }

    @Test
    func commandConfirmedReplacementRequestsExplicitQueueDefaultsAfterReset() async {
        let songs = makeSongs()
        let queue = IdentifiedArray(uniqueElements: songs)
        let repeatProbe = SuspendedOperationProbe<Void>()
        let shuffleProbe = SuspendedOperationProbe<Void>()
        let repeatTargets = LockIsolated<[PlaybackRepeatMode]>([])
        let shuffleTargets = LockIsolated<[PlaybackShuffleMode]>([])
        let store = makeStore(
            queue: .init(
                songs: queue,
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            pendingOperation: .queueReplacement(
                .init(
                    requestID: UUID(7),
                    songs: queue,
                    startingItemID: songs[1].id
                )
            )
        ) {
            $0.playbackQueue.setRepeat = { target in
                repeatTargets.withValue { $0.append(target) }
                try await repeatProbe.run()
            }
            $0.playbackQueue.setShuffle = { target in
                shuffleTargets.withValue { $0.append(target) }
                try await shuffleProbe.run()
            }
        }

        await store.send(.queueReplacementSucceeded(requestID: UUID(7))) {
            $0.pendingOperation = nil
            $0.status = .playing
            $0.failure = nil
        }
        await store.receive(
            .queue(.replace(queue, startingAt: songs[1].id))
        ) {
            $0.queue.currentItemID = songs[1].id
        }
        await store.receive(.timeline(.reset))
        await store.receive(.requestQueueDefaults)
        await store.receive(.queue(.repeatModeChangeRequested(.off))) {
            $0.queue.pendingRepeatChange = .init(
                requestID: UUID(0),
                target: .off
            )
        }
        await store.receive(.queue(.shuffleModeChangeRequested(.off))) {
            $0.queue.pendingShuffleChange = .init(
                requestID: UUID(1),
                target: .off
            )
        }
        await repeatProbe.waitUntilStarted()
        await shuffleProbe.waitUntilStarted()

        #expect(repeatTargets.value == [.off])
        #expect(shuffleTargets.value == [.off])

        repeatProbe.succeed()
        await store.receive(
            .queue(.repeatModeChangeSucceeded(requestID: UUID(0)))
        ) {
            $0.queue.pendingRepeatChange = nil
        }
        shuffleProbe.succeed()
        await store.receive(
            .queue(.shuffleModeChangeSucceeded(requestID: UUID(1)))
        ) {
            $0.queue.pendingShuffleChange = nil
        }
    }

    @Test
    func snapshotConfirmedReplacementRequestsQueueDefaultsAfterReset() async {
        let songs = makeSongs()
        let queue = IdentifiedArray(uniqueElements: songs)
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: true,
            supportsQueueTransitions: true,
            supportedRepeatModes: [.off],
            supportsShuffle: false
        )
        let snapshot = makeSnapshot(
            itemID: songs[1].id,
            status: .playing,
            currentTime: 7
        )
        let store = makeStore(
            capabilities: capabilities,
            pendingOperation: .queueReplacement(
                .init(
                    requestID: UUID(7),
                    songs: queue,
                    startingItemID: songs[1].id
                )
            )
        )

        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.off)))
        await store.receive(.queue(.shuffleModeObserved(.off)))
        await store.receive(.reconcileSnapshot(snapshot)) {
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
        await store.receive(.requestQueueDefaults)
        await store.receive(.timeline(.positionObserved(7))) {
            $0.timeline.confirmedPosition = 7
        }
    }

    @Test
    func queueDefaultsRequestSendsOnlySupportedResets() async {
        let song = makeSong(nativeID: "song")
        let queue = PlaybackQueueFeature.State(
            songs: .init(uniqueElements: [song]),
            currentItemID: song.id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
        let repeatOnlyCapabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: true,
            supportsQueueTransitions: true,
            supportedRepeatModes: [.off, .one],
            supportsShuffle: false
        )
        let repeatOnlyStore = makeStore(
            queue: queue,
            capabilities: repeatOnlyCapabilities
        ) {
            $0.playbackQueue.setRepeat = { _ in }
        }

        await repeatOnlyStore.send(.requestQueueDefaults)
        await repeatOnlyStore.receive(
            .queue(.repeatModeChangeRequested(.off))
        ) {
            $0.queue.pendingRepeatChange = .init(
                requestID: UUID(0),
                target: .off
            )
        }
        await repeatOnlyStore.receive(
            .queue(.repeatModeChangeSucceeded(requestID: UUID(0)))
        ) {
            $0.queue.pendingRepeatChange = nil
        }

        let shuffleOnlyCapabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: true,
            supportsQueueTransitions: true,
            supportedRepeatModes: [.off],
            supportsShuffle: true
        )
        let shuffleOnlyStore = makeStore(
            queue: queue,
            capabilities: shuffleOnlyCapabilities
        ) {
            $0.playbackQueue.setShuffle = { _ in }
        }

        await shuffleOnlyStore.send(.requestQueueDefaults)
        await shuffleOnlyStore.receive(
            .queue(.shuffleModeChangeRequested(.off))
        ) {
            $0.queue.pendingShuffleChange = .init(
                requestID: UUID(0),
                target: .off
            )
        }
        await shuffleOnlyStore.receive(
            .queue(.shuffleModeChangeSucceeded(requestID: UUID(0)))
        ) {
            $0.queue.pendingShuffleChange = nil
        }

        let unsupportedCapabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: true,
            supportsQueueTransitions: true,
            supportedRepeatModes: [.off],
            supportsShuffle: false
        )
        let unsupportedStore = makeStore(
            queue: queue,
            capabilities: unsupportedCapabilities
        )

        await unsupportedStore.send(.requestQueueDefaults)
    }

    @Test
    func modeChangeFailureSurfacesThroughTheParent() async {
        let song = makeSong(nativeID: "song")
        let store = makeStore(
            queue: .init(
                songs: .init(uniqueElements: [song]),
                currentItemID: song.id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: .init(
                    requestID: UUID(0),
                    target: .one
                ),
                pendingShuffleChange: nil
            )
        )

        await store.send(
            .queue(
                .repeatModeChangeFailed(
                    requestID: UUID(0),
                    error: .playbackFailed
                )
            )
        ) {
            $0.queue.pendingRepeatChange = nil
        }
        await store.receive(
            .queue(.delegate(.modeChangeFailed(.playbackFailed)))
        ) {
            $0.failure = .playbackFailed
        }

        #expect(store.state.queue.repeatMode == .off)
    }

    @Test
    func selectionFreezesLoadedOrderAndReplacesQueueFromTappedItem() async {
        let songs = makeSongs()
        let loadedResults = IdentifiedArray(uniqueElements: songs)
        let calls = LockIsolated<[PlaybackQueueCall]>([])
        let store = makeStore(
            capabilities: capabilitiesWithoutQueueModeChanges
        ) {
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
        await store.receive(.requestQueueDefaults)

        let expectedCalls = [
            PlaybackQueueCall(
                itemIDs: Array(loadedResults.ids),
                startingItemID: songs[1].id
            )
        ]
        #expect(calls.value == expectedCalls)
    }

    @Test
    func pendingSelectionDoesNotReplaceConfirmedQueue() async {
        let confirmedSongs = makeSongs(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeSongs(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let probe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                songs: confirmedQueue,
                currentItemID: confirmedSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing
        ) {
            $0.playbackQueue.replace = { _, _ in
                try await probe.run()
            }
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
        let store = makeStore(
            capabilities: capabilitiesWithoutQueueModeChanges
        ) {
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
        await store.receive(.requestQueueDefaults)
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
            queue: .init(
                songs: queue,
                currentItemID: songs[1].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
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

        let expectedQueue = PlaybackQueueFeature.State(
            songs: queue,
            currentItemID: songs[1].id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
        #expect(store.state.queue == expectedQueue)
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
                supportsQueueTransitions: true,
                supportedRepeatModes: [.off, .all, .one],
                supportsShuffle: true
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
            queue: .init(
                songs: queue,
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            )
        )

        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.off)))
        await store.receive(.queue(.shuffleModeObserved(.off)))
        await store.receive(.reconcileSnapshot(snapshot)) {
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
            capabilities: capabilitiesWithoutQueueModeChanges,
            pendingOperation: .queueReplacement(pending)
        )

        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.off)))
        await store.receive(.queue(.shuffleModeObserved(.off)))
        await store.receive(.reconcileSnapshot(snapshot)) {
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
        await store.receive(.requestQueueDefaults)
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
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
        let expectedOperation = PlaybackFeature.PendingOperation.statusChange(
            .init(requestID: UUID(0), target: .paused)
        )
        #expect(store.state.pendingOperation == expectedOperation)
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
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
        let expectedOperation = PlaybackFeature.PendingOperation.statusChange(
            .init(requestID: UUID(0), target: .playing)
        )
        #expect(store.state.pendingOperation == expectedOperation)
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing,
            pendingOperation: .statusChange(pending)
        )

        #expect(!store.state.commandPolicy.allows(.playPause))
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
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

        #expect(store.state.commandPolicy.allows(.playPause))
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
        let statusProbe = SuspendedOperationProbe<Void>()
        let queueProbe = SuspendedOperationProbe<Void>()
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: status
        ) {
            switch target {
            case .playing:
                $0.playbackTransport.play = statusProbe.run
            case .paused:
                $0.playbackTransport.pause = statusProbe.run
            case .stopped:
                $0.playbackTransport.stop = statusProbe.run
            }
            $0.playbackQueue.replace = { _, _ in
                try await queueProbe.run()
            }
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
        let queueProbe = SuspendedOperationProbe<Void>()
        let stopProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            status: .playing
        ) {
            $0.playbackQueue.replace = { _, _ in
                try await queueProbe.run()
            }
            $0.playbackTransport.stop = stopProbe.run
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

        #expect(store.state.commandPolicy.allows(.stop))
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
        #expect(!store.state.commandPolicy.allows(.stop))
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing,
            pendingOperation: .statusChange(pending)
        )

        await store.send(.statusChangeSucceeded(requestID: UUID(0)))
        #expect(store.state.pendingOperation == .statusChange(pending))
        await store.send(.statusChangeSucceeded(requestID: UUID(1)))
        #expect(store.state.pendingOperation == .statusChange(pending))
        #expect(store.state.status == .playing)

        let snapshot = makeSnapshot(
            itemID: songs[0].id,
            status: .paused,
            currentTime: 12
        )
        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.off)))
        await store.receive(.queue(.shuffleModeObserved(.off)))
        await store.receive(.reconcileSnapshot(snapshot)) {
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing,
            timeline: .init(confirmedPosition: 4, interaction: .idle),
            pendingOperation: .statusChange(pending)
        )

        let snapshot = makeSnapshot(
            itemID: songs[0].id,
            status: .paused,
            currentTime: 7
        )
        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.off)))
        await store.receive(.queue(.shuffleModeObserved(.off)))
        await store.receive(.reconcileSnapshot(snapshot)) {
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing,
            timeline: .init(confirmedPosition: 42, interaction: .dragging(position: 50)),
            pendingOperation: .statusChange(pending)
        )

        let snapshot = makeSnapshot(
            itemID: songs[0].id,
            status: .stopped,
            currentTime: 9
        )
        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.off)))
        await store.receive(.queue(.shuffleModeObserved(.off)))
        await store.receive(.reconcileSnapshot(snapshot)) {
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
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
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
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

        let snapshot = makeSnapshot(
            itemID: songs[0].id,
            status: .stopped,
            currentTime: 0
        )
        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.off)))
        await store.receive(.queue(.shuffleModeObserved(.off)))
        await store.receive(.reconcileSnapshot(snapshot)) {
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
            queue: .init(
                songs: songs,
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing,
            failure: nil,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: .init(confirmedPosition: 0, interaction: .idle),
            pendingOperation: nil,
            pendingProviderReset: nil,
            isPlayerPresented: false
        )
        let replacing = PlaybackFeature.State(
            providerID: providerID,
            queue: .init(
                songs: [],
                currentItemID: nil,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .stopped,
            failure: nil,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: .init(confirmedPosition: 0, interaction: .idle),
            pendingOperation: .queueReplacement(
                .init(requestID: UUID(0), songs: songs, startingItemID: songs[0].id)
            ),
            pendingProviderReset: nil,
            isPlayerPresented: false
        )

        #expect(active.commandPolicy.allows(.playPause))
        #expect(active.commandPolicy.allows(.stop))
        #expect(!replacing.commandPolicy.allows(.playPause))
        #expect(replacing.commandPolicy.allows(.stop))
    }

    @Test
    func oldProviderSnapshotIsIgnoredDuringResetWindow() async {
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(pendingProviderReset: pendingProviderReset)
        let staleSnapshot = PlaybackSnapshot(
            currentItemID: nil,
            status: .playing,
            currentTime: 99,
            playbackRate: .normal,
            repeatMode: .off,
            shuffleMode: .off
        )

        await store.send(.snapshotReceived(staleSnapshot))
        await store.send(.reconcileSnapshot(staleSnapshot))

        #expect(store.state.status == .idle)
        #expect(store.state.timeline.confirmedPosition == 0)
        #expect(
            store.state.pendingProviderReset == pendingProviderReset
        )
    }

    @Test
    func staleApplyResetCannotFinalizeRepeatedProviderReset() async {
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(1),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(pendingProviderReset: pendingProviderReset)

        await store.send(.applyReset(requestID: UUID(0)))

        #expect(
            store.state.pendingProviderReset == pendingProviderReset
        )
        #expect(store.state.providerID == providerID)
    }

    @Test
    func resetWindowRejectsNewParentOperations() async {
        let songs = IdentifiedArray(uniqueElements: makeSongs())
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(
            queue: .init(
                songs: songs,
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing,
            pendingProviderReset: pendingProviderReset
        )

        #expect(!store.state.commandPolicy.allows(.playPause))
        #expect(!store.state.commandPolicy.allows(.stop))
        await store.send(
            .selectionReceived(
                songs[1],
                loadedResults: songs,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )

        #expect(store.state.pendingOperation == nil)
        #expect(
            store.state.pendingProviderReset == pendingProviderReset
        )
    }

    @Test
    func resetWindowRejectsQueuedPlaybackEffects() async {
        let songs = IdentifiedArray(uniqueElements: makeSongs())
        let pendingOperation = PlaybackFeature.PendingOperation.statusChange(
            .init(requestID: UUID(1), target: .paused)
        )
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let calls = LockIsolated(0)
        let store = makeStore(
            queue: .init(
                songs: songs,
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing,
            pendingOperation: pendingOperation,
            pendingProviderReset: pendingProviderReset
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
        #expect(
            store.state.pendingProviderReset == pendingProviderReset
        )
    }

    @Test
    func resetWindowRejectsIneligibleSelectionPresentation() async {
        let songs = IdentifiedArray(uniqueElements: makeSongs())
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: providerID,
            capabilities: .allEnabled
        )
        let store = makeStore(pendingProviderReset: pendingProviderReset)

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
        #expect(
            store.state.pendingProviderReset == pendingProviderReset
        )
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
        let firstSeek = SuspendedOperationProbe<Void>()
        let replacementSeek = SuspendedOperationProbe<Void>()
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
                    try await firstSeek.run()
                } else {
                    try await replacementSeek.run()
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
        #expect(firstSeek.hasObservedCancellation)
        await replacementSeek.waitUntilStarted()
        #expect(!replacementSeek.hasObservedCancellation)

        firstSeek.succeed()
        await store.send(.timeline(.seekSucceeded(requestID: UUID(0))))
        let expectedInteraction = PlaybackTimelineFeature.Interaction.seeking(
            requestID: UUID(1),
            position: 45
        )
        #expect(store.state.timeline.interaction == expectedInteraction)

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
            supportsQueueTransitions: capabilities.supportsQueueTransitions,
            supportedRepeatModes: capabilities.supportedRepeatModes,
            supportsShuffle: capabilities.supportsShuffle
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
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(
            queue: makeQueue(duration: 180),
            pendingProviderReset: pendingProviderReset
        )

        await store.send(.timelinePositionChanged(30))
        await store.send(.timelineInteractionEnded)
        await store.send(.restartTapped)
        await store.send(.seekBackwardTapped)
        await store.send(.seekForwardTapped)
    }

    @Test(arguments: [
        PlaybackQueueNavigationDirection.previous,
        .next,
    ])
    func parentRoutesAuthorizedQueueTransitionToTheQueueChild(
        direction: PlaybackQueueNavigationDirection
    ) async {
        let songs = makeSongs()
        let calls = LockIsolated<[PlaybackQueueNavigationDirection]>([])
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[1].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            )
        ) {
            $0.playbackQueue.navigate = { direction in
                calls.withValue { $0.append(direction) }
                return .accepted
            }
        }

        let action: PlaybackFeature.Action =
            direction == .previous ? .previousTapped : .nextTapped
        await store.send(action)
        await store.receive(.queue(.queueTransitionRequested(direction))) {
            $0.queue.pendingQueueTransition = .init(
                requestID: UUID(0),
                direction: direction
            )
        }
        await store.finish()

        #expect(calls.value == [direction])
        #expect(store.state.queue.currentItemID == songs[1].id)
        #expect(store.state.queue.pendingQueueTransition != nil)
    }

    @Test
    func unsupportedAndUnresolvedQueueTransitionsAreTrueNoOps() async {
        let songs = makeSongs()
        let unsupported = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: true,
            supportsQueueTransitions: false,
            supportedRepeatModes: [.off, .all, .one],
            supportsShuffle: true
        )
        let unsupportedStore = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: nil,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            capabilities: unsupported
        )
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(7),
            direction: .next
        )
        let unresolvedStore = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: pending,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            )
        )

        #expect(!unsupportedStore.state.commandPolicy.allows(.previous))
        #expect(!unresolvedStore.state.commandPolicy.allows(.next))
        await unsupportedStore.send(.nextTapped)
        await unresolvedStore.send(.previousTapped)
    }

    @Test
    func providerSnapshotAloneConfirmsTheQueueTransition() async {
        let songs = makeSongs()
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: .init(
                    requestID: UUID(0),
                    direction: .next
                ),
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing
        )

        let snapshot = makeSnapshot(
            itemID: songs[1].id,
            status: .playing,
            currentTime: 0
        )
        await store.send(.snapshotReceived(snapshot))
        await store.receive(.queue(.repeatModeObserved(.off)))
        await store.receive(.queue(.shuffleModeObserved(.off)))
        await store.receive(.reconcileSnapshot(snapshot))
        await store.receive(.queue(.currentItemObserved(songs[1].id))) {
            $0.queue.currentItemID = songs[1].id
            $0.queue.pendingQueueTransition = nil
        }
        await store.receive(.timeline(.positionObserved(0)))

        #expect(store.state.queue.currentItem == songs[1])
    }

    @Test
    func queueTransitionFailureSurfacesThroughTheParentWithoutChangingQueue() async {
        let songs = makeSongs()
        let pending = PlaybackQueueFeature.PendingQueueTransition(
            requestID: UUID(0),
            direction: .next
        )
        let store = makeStore(
            queue: .init(
                songs: IdentifiedArray(uniqueElements: songs),
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: pending,
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            )
        )

        await store.send(
            .queue(
                .queueTransitionFailed(
                    requestID: UUID(0),
                    error: .playbackFailed
                )
            )
        ) {
            $0.queue.pendingQueueTransition = nil
        }
        await store.receive(
            .queue(.delegate(.queueTransitionFailed(.playbackFailed)))
        ) {
            $0.failure = .playbackFailed
        }

        #expect(store.state.queue.currentItemID == songs[0].id)
    }

    @Test
    func queueReplacementCancelsPendingQueueTransitionBeforeProviderWork() async {
        let songs = makeSongs()
        let currentQueue = IdentifiedArray(uniqueElements: songs)
        let replacementSongs = makeSongs(prefix: "replacement")
        let replacementQueue = IdentifiedArray(uniqueElements: replacementSongs)
        let replacementProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: .init(
                songs: currentQueue,
                currentItemID: songs[0].id,
                repeatMode: .off,
                shuffleMode: .off,
                pendingQueueTransition: .init(
                    requestID: UUID(99),
                    direction: .next
                ),
                pendingRepeatChange: nil,
                pendingShuffleChange: nil
            ),
            status: .playing
        ) {
            $0.playbackQueue.replace = { _, _ in
                try await replacementProbe.run()
            }
        }

        await store.send(
            .selectionReceived(
                replacementSongs[0],
                loadedResults: replacementQueue,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingOperation = .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: replacementQueue,
                    startingItemID: replacementSongs[0].id
                )
            )
            $0.playbackEligibility = .eligible
            $0.failure = nil
        }
        await store.receive(.queue(.cancelQueueTransition)) {
            $0.queue.pendingQueueTransition = nil
        }
        await store.receive(
            .performQueueReplacement(
                requestID: UUID(0),
                itemIDs: Array(replacementQueue.ids),
                startingItemID: replacementSongs[0].id
            )
        )
        await replacementProbe.waitUntilStarted()
        await store.send(.cancelPendingOperation) {
            $0.pendingOperation = nil
        }
        await replacementProbe.waitUntilCancelled()

        #expect(store.state.queue.currentItemID == songs[0].id)
    }

    // MARK: - Helpers

    private let providerID = ProviderID(rawValue: "fake")

    private var capabilitiesWithoutQueueModeChanges: MusicProviderCapabilities {
        MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: true,
            supportsQueueTransitions: true,
            supportedRepeatModes: [.off],
            supportsShuffle: false
        )
    }

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
            currentItemID: song.id,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
        )
    }

    private func makeStore(
        queue: PlaybackQueueFeature.State = .init(
            songs: [],
            currentItemID: nil,
            repeatMode: .off,
            shuffleMode: .off,
            pendingQueueTransition: nil,
            pendingRepeatChange: nil,
            pendingShuffleChange: nil
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
        pendingProviderReset: PlaybackFeature.PendingProviderReset? = nil,
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
                pendingProviderReset: pendingProviderReset,
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
        currentTime: TimeInterval,
        repeatMode: PlaybackRepeatMode = .off,
        shuffleMode: PlaybackShuffleMode = .off
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            currentItemID: itemID,
            status: status,
            currentTime: currentTime,
            playbackRate: .normal,
            repeatMode: repeatMode,
            shuffleMode: shuffleMode
        )
    }
}

private struct PlaybackQueueCall: Equatable {
    let itemIDs: [MusicItemID]
    let startingItemID: MusicItemID
}
