import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackFeatureTests {
    @Test
    func repeatTapRoutesTheCycleToTheQueueChild() async {
        let song = makeTrack(nativeID: "song")
        let queue = PlaybackQueueFeature.State(
            tracks: .init(uniqueElements: [song]),
            playbackOrder: PlaybackQueueOrder(trackIDs: [song.id]),
            currentTrackID: song.id,
            repeatMode: .off,
            shuffleMode: .off
        )
        let store = makeStore(queue: queue)

        await store.send(.repeatTapped)
        await store.receive(.queue(.repeatTapped)) {
            $0.queue.repeatMode = .all
        }
    }

    @Test
    func shuffleTapRoutesTargetSelectionToTheQueueChild() async {
        let song = makeTrack(nativeID: "song")
        let queue = PlaybackQueueFeature.State(
            tracks: .init(uniqueElements: [song]),
            playbackOrder: PlaybackQueueOrder(trackIDs: [song.id]),
            currentTrackID: song.id,
            repeatMode: .off,
            shuffleMode: .off
        )
        let store = makeStore(queue: queue) {
            $0.playbackShuffle.shuffle = { $0 }
        }

        await store.send(.shuffleTapped)
        await store.receive(.queue(.shuffleTapped)) {
            $0.queue.shuffleMode = .tracks
        }
    }

    @Test
    func repeatChangeLeavesIndependentCommandsAuthorized() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[1].id,
                repeatMode: .off,
                shuffleMode: .off
            )
        )

        await store.send(.repeatTapped)
        await store.receive(.queue(.repeatTapped)) {
            $0.queue.repeatMode = .all
        }

        #expect(store.state.canRequestRepeat)
        #expect(store.state.canRequestShuffle)
        #expect(store.state.canRequestNext)
        #expect(store.state.canRequestSeek)
    }

    // MARK: - Pending Playback Transition Workflow

    @Test
    func selectionFreezesLoadedResultsIntoOnePendingTransition() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[1].id)
        )
        await probe.waitUntilStarted()

        #expect(store.state.pendingPlaybackTransition?.queue == loadedResults)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func laterLoadedResultsCannotMutateTheFrozenTransitionQueue() async {
        let firstPage = makeTracks(prefix: "first")
        let frozenResults = IdentifiedArray(uniqueElements: firstPage)
        let laterResults = IdentifiedArray(
            uniqueElements: firstPage + [makeTrack(nativeID: "later")]
        )
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(
            .selectionReceived(
                firstPage[0].id,
                loadedResults: frozenResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: frozenResults,
                targetTrackID: firstPage[0].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: firstPage[0].id)
        )
        await probe.waitUntilStarted()

        await store.send(
            .selectionReceived(
                firstPage[0].id,
                loadedResults: laterResults,
                providerID: "other",
                playbackEligibility: .eligible
            )
        )

        #expect(store.state.pendingPlaybackTransition?.queue == frozenResults)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func firstSelectionPresentsTheFullPlayer() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(
            .selectionReceived(
                tracks[0].id,
                loadedResults: loadedResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[0].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[0].id)
        )
        await probe.waitUntilStarted()

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func laterSelectionDoesNotRepresentADismissedPlayer() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(
            .selectionReceived(
                nextSongs[0].id,
                loadedResults: nextResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[0].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: nextSongs[0].id)
        )
        await probe.waitUntilStarted()

        #expect(!store.state.isPlayerPresented)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func confirmedPlaybackSurvivesWhileTheNextTrackResolves() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let timeline = PlaybackTimelineFeature.State(
            confirmedPosition: 42,
            interaction: .idle
        )
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            timeline: timeline
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(
            .selectionReceived(
                nextSongs[1].id,
                loadedResults: nextResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[1].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: nextSongs[1].id)
        )
        await probe.waitUntilStarted()

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == confirmedSongs[0])
        #expect(store.state.status == .playing)
        #expect(store.state.timeline == timeline)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func confirmedPlaybackSurvivesWhileTheNextTrackLoads() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let resource = makeResource(for: nextSongs[1].id)
        let timeline = PlaybackTimelineFeature.State(
            confirmedPosition: 42,
            interaction: .idle
        )
        let probe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            timeline: timeline
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _ in try await probe.run() }
        }

        await store.send(
            .selectionReceived(
                nextSongs[1].id,
                loadedResults: nextResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[1].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: nextSongs[1].id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await probe.waitUntilStarted()

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == confirmedSongs[0])
        #expect(store.state.status == .playing)
        #expect(store.state.timeline == timeline)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func resolutionReceivesOnlyTheTargetTrackIdentity() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[1].id)
        let resolvedTrackIDs = LockIsolated<[TrackID]>([])
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { trackID in
                resolvedTrackIDs.withValue { $0.append(trackID) }
                return resource
            }
            $0.playbackItem.load = { _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[1].id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0)))
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        #expect(resolvedTrackIDs.value == [tracks[1].id])
    }

    @Test
    func itemLoadingReceivesTheResolvedResourceWithoutADuplicateIdentity() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[1].id)
        let loadedResources = LockIsolated<[PlaybackResource]>([])
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { loaded in
                loadedResources.withValue { $0.append(loaded) }
            }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[1].id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0)))
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        #expect(loadedResources.value == [resource])
        #expect(loadedResources.value.map(\.trackID) == [tracks[1].id])
    }

    @Test
    func playIsRequestedOnlyAfterItemLoadingSucceeds() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[1].id)
        let calls = LockIsolated<[String]>([])
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                calls.withValue { $0.append("resolve") }
                return resource
            }
            $0.playbackItem.load = { _ in
                calls.withValue { $0.append("load") }
            }
            $0.playbackTransport.play = {
                calls.withValue { $0.append("play") }
            }
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[1].id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0)))
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        #expect(calls.value == ["resolve", "load", "play"])
    }

    @Test
    func noWorkflowStageConfirmsTheTargetTrack() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[1].id)
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[1].id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0)))
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        #expect(store.state.queue.tracks.isEmpty)
        #expect(store.state.queue.currentTrackID == nil)
        #expect(store.state.status == .idle)
        #expect(store.state.timeline.confirmedPosition == 0)
        let expectedTransition = PendingPlaybackTransition(
            requestID: UUID(0),
            queue: loadedResults,
            targetTrackID: tracks[1].id
        )
        #expect(store.state.pendingPlaybackTransition == expectedTransition)
    }

    @Test
    func matchingPlayingSnapshotConfirmsThePendingTransition() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let pending = PendingPlaybackTransition(
            requestID: UUID(0),
            queue: loadedResults,
            targetTrackID: tracks[1].id
        )
        let snapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .playing,
            position: 7
        )
        let store = makeStore(pendingPlaybackTransition: pending)

        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.status = .playing
            $0.pendingPlaybackTransition = nil
        }
        await store.receive(
            .queue(.replace(loadedResults, startingAt: tracks[1].id))
        ) {
            $0.queue.tracks = loadedResults
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: tracks.map(\.id)
            )
            $0.queue.currentTrackID = tracks[1].id
        }
        await store.receive(.timeline(.positionObserved(7))) {
            $0.timeline.confirmedPosition = 7
        }

        #expect(store.state.queue.currentTrack == tracks[1])
        #expect(store.state.pendingPlaybackTransition == nil)
    }

    @Test
    func newerSelectionCancelsTheEarlierTransitionAndIgnoresStaleResponses() async {
        let firstSongs = makeTracks(prefix: "first")
        let firstResults = IdentifiedArray(uniqueElements: firstSongs)
        let secondSongs = makeTracks(prefix: "second")
        let secondResults = IdentifiedArray(uniqueElements: secondSongs)
        let staleResource = makeResource(for: firstSongs[0].id)
        let firstProbe = SuspendedOperationProbe<PlaybackResource>()
        let secondProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { trackID in
                if trackID == firstSongs[0].id {
                    return try await firstProbe.run()
                }
                return try await secondProbe.run()
            }
        }

        await store.send(
            .selectionReceived(
                firstSongs[0].id,
                loadedResults: firstResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: firstResults,
                targetTrackID: firstSongs[0].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: firstSongs[0].id)
        )
        await firstProbe.waitUntilStarted()

        await store.send(
            .selectionReceived(
                secondSongs[1].id,
                loadedResults: secondResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: secondResults,
                targetTrackID: secondSongs[1].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(1), trackID: secondSongs[1].id)
        )
        await firstProbe.waitUntilCancelled()
        await secondProbe.waitUntilStarted()

        #expect(firstProbe.hasObservedCancellation)
        #expect(!secondProbe.hasObservedCancellation)

        await store.send(
            .transitionResourceResolved(
                requestID: UUID(0),
                resource: staleResource
            )
        )
        await store.send(.transitionItemLoaded(requestID: UUID(0)))
        await store.send(.transitionPlayRequested(requestID: UUID(0)))
        await store.send(
            .transitionResolutionFailed(
                requestID: UUID(0),
                failure: .resourceUnavailable
            )
        )

        let expectedTransition = PendingPlaybackTransition(
            requestID: UUID(1),
            queue: secondResults,
            targetTrackID: secondSongs[1].id
        )
        #expect(store.state.pendingPlaybackTransition == expectedTransition)
        #expect(store.state.failureNotice == nil)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await secondProbe.waitUntilCancelled()
    }

    @Test
    func failedResolutionClearsOnlyTheMatchingTransition() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let timeline = PlaybackTimelineFeature.State(
            confirmedPosition: 42,
            interaction: .dragging(position: 50)
        )
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[1].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .paused,
            timeline: timeline,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[0].id
            )
        )

        await store.send(
            .transitionResolutionFailed(
                requestID: UUID(1),
                failure: .resourceUnavailable
            )
        )
        await store.send(
            .transitionResolutionFailed(
                requestID: UUID(0),
                failure: .resourceUnavailable
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: nextSongs[0].id,
                failure: .resourceUnavailable
            )
            $0.pendingPlaybackTransition = nil
        }

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == confirmedSongs[1])
        #expect(store.state.status == .paused)
        #expect(store.state.timeline == timeline)
    }

    @Test
    func failedItemLoadClearsTheTransitionAndNeverRequestsPlay() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let resource = makeResource(for: nextSongs[0].id)
        let playCalls = LockIsolated(0)
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[1].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _ in
                throw PlaybackFailure.preparationFailed
            }
            $0.playbackTransport.play = {
                playCalls.withValue { $0 += 1 }
            }
        }

        await store.send(
            .selectionReceived(
                nextSongs[0].id,
                loadedResults: nextResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[0].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: nextSongs[0].id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .transitionItemLoadFailed(
                requestID: UUID(0),
                failure: .preparationFailed
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: nextSongs[0].id,
                failure: .preparationFailed
            )
            $0.pendingPlaybackTransition = nil
        }

        #expect(playCalls.value == 0)
        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.status == .playing)
    }

    @Test
    func failedPlayRequestClearsTheTransitionAndPreservesConfirmedPlayback() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let resource = makeResource(for: nextSongs[0].id)
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[1].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _ in }
            $0.playbackTransport.play = {
                throw MusicProviderError.playbackFailed
            }
        }

        await store.send(
            .selectionReceived(
                nextSongs[0].id,
                loadedResults: nextResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[0].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: nextSongs[0].id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0)))
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(
            .transitionPlayFailed(requestID: UUID(0), failure: .playbackFailed)
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: nextSongs[0].id,
                failure: .playbackFailed
            )
            $0.pendingPlaybackTransition = nil
        }

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == confirmedSongs[1])
        #expect(store.state.status == .playing)
    }

    @Test
    func missingProviderRegistrationFailsClosed() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore {
            $0.playbackResourceClients = ProviderClientRegistry(clients: [:])
        }

        await store.send(
            .selectionReceived(
                tracks[0].id,
                loadedResults: loadedResults,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[0].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[0].id)
        )
        await store.receive(
            .transitionResolutionFailed(
                requestID: UUID(0),
                failure: .resourceUnavailable
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[0].id,
                failure: .resourceUnavailable
            )
            $0.pendingPlaybackTransition = nil
        }
    }

    @Test
    func invalidSelectionsNeverStartATransition() async {
        let resolveCalls = LockIsolated(0)
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[0].id)
        let anotherProviderSongs = [
            tracks[0],
            makeTrack(providerID: "other", nativeID: "other"),
        ]
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resolveCalls.withValue { $0 += 1 }
                return resource
            }
        }

        await store.send(
            .selectionReceived(
                TrackID(providerID: providerID, nativeID: "missing"),
                loadedResults: queue,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )
        await store.send(
            .selectionReceived(
                tracks[0].id,
                loadedResults: IdentifiedArray(
                    uniqueElements: anotherProviderSongs
                ),
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )
        await store.send(
            .selectionReceived(
                tracks[0].id,
                loadedResults: queue,
                providerID: "other",
                playbackEligibility: .eligible
            )
        )
        await store.send(
            .selectionReceived(
                tracks[0].id,
                loadedResults: queue,
                providerID: providerID,
                playbackEligibility: .ineligible
            )
        ) {
            $0.playbackEligibility = .ineligible
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
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resolveCalls.withValue { $0 += 1 }
                return resource
            }
        }
        await unsupportedStore.send(
            .selectionReceived(
                tracks[0].id,
                loadedResults: queue,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )

        #expect(resolveCalls.value == 0)
    }

    @Test
    func selectionSupersedesAPendingStatusChange() async {
        let tracks = makeTracks()
        let replacement = IdentifiedArray(
            uniqueElements: makeTracks(prefix: "next")
        )
        let statusProbe = SuspendedOperationProbe<Void>()
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackTransport.pause = statusProbe.run
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await resolveProbe.run()
            }
        }

        await store.send(.playPauseTapped) {
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(0),
                target: .paused
            )
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .paused)
        )
        await statusProbe.waitUntilStarted()

        await store.send(
            .selectionReceived(
                replacement[0].id,
                loadedResults: replacement,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: replacement,
                targetTrackID: replacement[0].id
            )
            $0.pendingStatusChange = nil
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(1), trackID: replacement[0].id)
        )
        await statusProbe.waitUntilCancelled()
        await resolveProbe.waitUntilStarted()

        #expect(statusProbe.hasObservedCancellation)
        #expect(store.state.pendingStatusChange == nil)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await resolveProbe.waitUntilCancelled()
    }

    @Test
    func selectionSupersedesAnUnresolvableStatusChange() async {
        let tracks = makeTracks()
        let replacement = IdentifiedArray(
            uniqueElements: makeTracks(prefix: "next")
        )
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackTransport.pause = {}
            $0.playbackResourceClients = self.makeResourceClients { _ in
                throw PlaybackFailure.resourceUnavailable
            }
        }

        await store.send(.playPauseTapped) {
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(0),
                target: .paused
            )
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .paused)
        )
        await store.receive(.statusChangeSucceeded(requestID: UUID(0)))

        await store.send(
            .selectionReceived(
                replacement[0].id,
                loadedResults: replacement,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: replacement,
                targetTrackID: replacement[0].id
            )
            $0.pendingStatusChange = nil
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(1), trackID: replacement[0].id)
        )
        await store.receive(
            .transitionResolutionFailed(
                requestID: UUID(1),
                failure: .resourceUnavailable
            )
        ) {
            $0.pendingPlaybackTransition = nil
            $0.failureNotice = PlaybackFailureNotice(
                trackID: replacement[0].id,
                failure: .resourceUnavailable
            )
        }

        // The player keeps playing, so the abandoned pause target never matches.
        let snapshot = makeSnapshot(
            itemID: tracks[0].id,
            status: .playing,
            position: 12
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot))
        await store.receive(.queue(.currentTrackConfirmed(tracks[0].id)))
        await store.receive(.timeline(.positionObserved(12))) {
            $0.timeline.confirmedPosition = 12
        }

        #expect(store.state.pendingStatusChange == nil)
        #expect(store.state.canRequestPlayPause)
        #expect(store.state.canRequestStop)
    }

    @Test
    func stopDuringATransitionAbortsTheTransitionAndBlocksAnotherStop() async {
        let tracks = makeTracks()
        let replacement = IdentifiedArray(
            uniqueElements: makeTracks(prefix: "next")
        )
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let stopProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await resolveProbe.run()
            }
            $0.playbackTransport.pause = stopProbe.run
        }

        await store.send(
            .selectionReceived(
                replacement[0].id,
                loadedResults: replacement,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: replacement,
                targetTrackID: replacement[0].id
            )
            $0.playbackEligibility = .eligible
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: replacement[0].id)
        )
        await resolveProbe.waitUntilStarted()

        #expect(store.state.canRequestStop)
        await store.send(.stopTapped) {
            $0.pendingPlaybackTransition = nil
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(1),
                target: .stopped
            )
        }
        await store.receive(
            .performStatusChange(requestID: UUID(1), target: .stopped)
        )
        await resolveProbe.waitUntilCancelled()
        await stopProbe.waitUntilStarted()

        #expect(resolveProbe.hasObservedCancellation)
        #expect(store.state.pendingPlaybackTransition == nil)
        #expect(!store.state.canRequestStop)
        await store.send(.stopTapped)

        stopProbe.fail(with: MusicProviderError.playbackFailed)
        await store.receive(
            .statusChangeFailed(requestID: UUID(1), error: .playbackFailed)
        ) {
            $0.pendingStatusChange = nil
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[0].id,
                failure: .playbackFailed
            )
        }
    }

    // MARK: - Confirmed Playback

    @Test
    func unknownSnapshotItemDoesNotReplaceConfirmedMetadata() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let unknownID = TrackID(providerID: providerID, nativeID: "unknown")
        let snapshot = makeSnapshot(
            itemID: unknownID,
            status: .playing,
            position: 12
        )
        let store = makeStore(
            queue: .init(
                tracks: queue,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(queue.ids)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            )
        )

        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.status = .playing
        }
        await store.receive(.queue(.currentTrackConfirmed(unknownID)))
        await store.receive(.timeline(.positionObserved(12))) {
            $0.timeline.confirmedPosition = 12
        }

        #expect(store.state.queue.currentTrack == tracks[0])
    }

    @Test
    func observedFailureForCurrentTrackRecordsOneNoticeAndKeepsTheQueue() async {
        let tracks = makeTracks()
        let confirmedQueue = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[1].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        )

        await store.send(
            .observationReceived(.failed(tracks[1].id, .playbackFailed))
        )
        await store.receive(
            .runtimePlaybackFailed(tracks[1].id, .playbackFailed)
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[1].id,
                failure: .playbackFailed
            )
        }

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == tracks[1])
    }

    @Test
    func observedFailureForDifferentTrackIsIgnored() async {
        let queue = makeQueue(duration: 180)
        let otherTrackID = TrackID(
            providerID: providerID,
            nativeID: "different-track"
        )
        let store = makeStore(queue: queue)

        await store.send(
            .observationReceived(.failed(otherTrackID, .playbackFailed))
        )
        await store.receive(
            .runtimePlaybackFailed(otherTrackID, .playbackFailed)
        )

        #expect(store.state.failureNotice == nil)
    }

    @Test
    func playingPlayPauseStartsPendingPauseAndCallsOnlyPause() async {
        let tracks = makeTracks()
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
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
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(0),
                target: .paused
            )
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .paused)
        )
        await store.receive(.statusChangeSucceeded(requestID: UUID(0)))

        #expect(calls.value == ["pause"])
        #expect(store.state.status == .playing)
        let expectedChange = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .paused
        )
        #expect(store.state.pendingStatusChange == expectedChange)
    }

    @Test(arguments: [PlaybackStatus.paused, .stopped])
    func pausedOrStoppedPlayPauseStartsPendingPlayAndCallsOnlyResume(
        status: PlaybackStatus
    ) async {
        let tracks = makeTracks()
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
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
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(0),
                target: .playing
            )
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .playing)
        )
        await store.receive(.statusChangeSucceeded(requestID: UUID(0)))

        #expect(calls.value == ["resume"])
        #expect(store.state.status == status)
        let expectedChange = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .playing
        )
        #expect(store.state.pendingStatusChange == expectedChange)
    }

    @Test
    func stopTappedPausesThenSeeksToZeroInOrder() async {
        let tracks = makeTracks()
        let calls = LockIsolated<[String]>([])
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackTransport.pause = {
                calls.withValue { $0.append("pause") }
            }
            $0.playbackTimeline.seek = { time in
                calls.withValue { $0.append("seek:\(time)") }
            }
        }

        await store.send(.stopTapped) {
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(0),
                target: .stopped
            )
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .stopped)
        )
        await store.receive(.statusChangeSucceeded(requestID: UUID(0))) {
            $0.status = .stopped
            $0.pendingStatusChange = nil
        }
        await store.receive(.timeline(.reset))

        #expect(calls.value == ["pause", "seek:0.0"])
    }

    @Test
    func playPauseIsIgnoredWhileAStatusChangeIsPending() async {
        let tracks = makeTracks()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .paused
        )
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingStatusChange: pending
        )

        #expect(!store.state.canRequestPlayPause)
        await store.send(.playPauseTapped)
        #expect(store.state.pendingStatusChange == pending)
    }

    @Test
    func pendingStopBlocksAnotherPlayPauseRequest() async {
        let tracks = makeTracks()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(99),
            target: .stopped
        )
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingStatusChange: pending
        )

        #expect(!store.state.canRequestPlayPause)
        await store.send(.playPauseTapped)
        #expect(store.state.pendingStatusChange == pending)
    }

    @Test
    func successfulStatusCommandWaitsForMatchingSnapshot() async {
        let tracks = makeTracks()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(1),
            target: .paused
        )
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingStatusChange: pending
        )

        await store.send(.statusChangeSucceeded(requestID: UUID(0)))
        #expect(store.state.pendingStatusChange == pending)
        await store.send(.statusChangeSucceeded(requestID: UUID(1)))
        #expect(store.state.pendingStatusChange == pending)
        #expect(store.state.status == .playing)

        let snapshot = makeSnapshot(
            itemID: tracks[0].id,
            status: .paused,
            position: 12
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.pendingStatusChange = nil
            $0.status = .paused
        }
        await store.receive(.queue(.currentTrackConfirmed(tracks[0].id)))
        await store.receive(.timeline(.positionObserved(12))) {
            $0.timeline.confirmedPosition = 12
        }
    }

    @Test
    func snapshotsKeepProviderTruthUntilTheyMatchPendingTarget() async {
        let tracks = makeTracks()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .stopped
        )
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            timeline: .init(confirmedPosition: 4, interaction: .idle),
            pendingStatusChange: pending
        )

        let snapshot = makeSnapshot(
            itemID: tracks[0].id,
            status: .paused,
            position: 7
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.status = .paused
        }
        await store.receive(.queue(.currentTrackConfirmed(tracks[0].id)))
        await store.receive(.timeline(.positionObserved(7))) {
            $0.timeline.confirmedPosition = 7
        }
        #expect(store.state.pendingStatusChange == pending)
        #expect(store.state.status == .paused)
        #expect(store.state.timeline.confirmedPosition == 7)
    }

    @Test
    func stoppedSnapshotConfirmationResetsTimelineWithoutApplyingSnapshotPosition() async {
        let tracks = makeTracks()
        let pending = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .stopped
        )
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            timeline: .init(
                confirmedPosition: 42,
                interaction: .dragging(position: 50)
            ),
            pendingStatusChange: pending
        )

        let snapshot = makeSnapshot(
            itemID: tracks[0].id,
            status: .stopped,
            position: 9
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.status = .stopped
            $0.pendingStatusChange = nil
        }
        await store.receive(.timeline(.reset)) {
            $0.timeline.confirmedPosition = 0
            $0.timeline.interaction = .idle
        }
        await store.receive(.queue(.currentTrackConfirmed(tracks[0].id)))

        #expect(store.state.timeline.confirmedPosition == 0)
    }

    @Test
    func failedStatusChangeClearsOnlyMatchingRequestAndPreservesConfirmedTruth() async {
        let tracks = makeTracks()
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
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .paused,
            timeline: timeline,
            pendingStatusChange: pending
        )

        await store.send(
            .statusChangeFailed(requestID: UUID(0), error: .network)
        )
        #expect(store.state.pendingStatusChange == pending)
        await store.send(
            .statusChangeFailed(requestID: UUID(1), error: .playbackFailed)
        ) {
            $0.pendingStatusChange = nil
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[0].id,
                failure: .playbackFailed
            )
        }

        #expect(store.state.status == .paused)
        #expect(store.state.timeline == timeline)
    }

    @Test
    func timelineResetsOnlyAfterStopSucceeds() async {
        let tracks = makeTracks()
        let stopProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            timeline: .init(
                confirmedPosition: 42,
                interaction: .dragging(position: 50)
            )
        ) {
            $0.playbackTransport.pause = {}
            $0.playbackTimeline.seek = { _ in try await stopProbe.run() }
        }

        await store.send(.stopTapped) {
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(0),
                target: .stopped
            )
        }
        await store.receive(
            .performStatusChange(requestID: UUID(0), target: .stopped)
        )
        await stopProbe.waitUntilStarted()

        #expect(store.state.status == .playing)
        #expect(store.state.timeline.confirmedPosition == 42)

        stopProbe.succeed()
        await store.receive(.statusChangeSucceeded(requestID: UUID(0))) {
            $0.status = .stopped
            $0.pendingStatusChange = nil
        }
        await store.receive(.timeline(.reset)) {
            $0.timeline.confirmedPosition = 0
            $0.timeline.interaction = .idle
        }
    }

    @Test
    func pausedAtZeroSnapshotDoesNotOverwriteConfirmedStop() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .stopped
        )

        let snapshot = makeSnapshot(
            itemID: tracks[0].id,
            status: .paused,
            position: 0
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot))
        await store.receive(.queue(.currentTrackConfirmed(tracks[0].id)))
        await store.receive(.timeline(.positionObserved(0)))

        #expect(store.state.status == .stopped)
    }

    @Test
    func playingSnapshotExitsConfirmedStop() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .stopped
        )

        let snapshot = makeSnapshot(
            itemID: tracks[0].id,
            status: .playing,
            position: 3
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.status = .playing
        }
        await store.receive(.queue(.currentTrackConfirmed(tracks[0].id)))
        await store.receive(.timeline(.positionObserved(3))) {
            $0.timeline.confirmedPosition = 3
        }
    }

    @Test
    func statusPermissionsMatchReducerPolicy() {
        let tracks = IdentifiedArray(uniqueElements: makeTracks())
        let active = PlaybackFeature.State(
            providerID: providerID,
            queue: .init(
                tracks: tracks,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(tracks.ids)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            failureNotice: nil,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: .init(confirmedPosition: 0, interaction: .idle),
            pendingPlaybackTransition: nil,
            pendingStatusChange: nil,
            pendingProviderReset: nil,
            isPlayerPresented: false
        )
        let transitioning = PlaybackFeature.State(
            providerID: providerID,
            queue: .init(
                tracks: [],
                playbackOrder: PlaybackQueueOrder(trackIDs: []),
                currentTrackID: nil,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .stopped,
            failureNotice: nil,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: .init(confirmedPosition: 0, interaction: .idle),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: tracks,
                targetTrackID: tracks[0].id
            ),
            pendingStatusChange: nil,
            pendingProviderReset: nil,
            isPlayerPresented: false
        )

        #expect(active.canRequestPlayPause)
        #expect(active.canRequestStop)
        #expect(!transitioning.canRequestPlayPause)
        #expect(!transitioning.canRequestStop)
    }

    // MARK: - Provider Reset

    @Test
    func oldProviderSnapshotIsIgnoredDuringResetWindow() async {
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(pendingProviderReset: pendingProviderReset)
        let staleSnapshot = PlaybackSnapshot(
            currentTrackID: nil,
            status: .playing,
            position: 99,
            duration: nil
        )

        await store.send(.observationReceived(.snapshot(staleSnapshot)))
        await store.receive(.reconcileSnapshot(staleSnapshot))
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
    func resetWindowRejectsNewSelections() async {
        let tracks = IdentifiedArray(uniqueElements: makeTracks())
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makeStore(
            queue: .init(
                tracks: tracks,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(tracks.ids)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingProviderReset: pendingProviderReset
        )

        #expect(!store.state.canRequestPlayPause)
        #expect(!store.state.canRequestStop)
        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: tracks,
                providerID: providerID,
                playbackEligibility: .eligible
            )
        )

        #expect(store.state.pendingPlaybackTransition == nil)
        #expect(
            store.state.pendingProviderReset == pendingProviderReset
        )
    }

    @Test
    func resetWindowRejectsQueuedPlaybackEffects() async {
        let tracks = IdentifiedArray(uniqueElements: makeTracks())
        let pendingStatusChange = PlaybackFeature.PendingStatusChange(
            requestID: UUID(1),
            target: .paused
        )
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let calls = LockIsolated(0)
        let store = makeStore(
            queue: .init(
                tracks: tracks,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(tracks.ids)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingStatusChange: pendingStatusChange,
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
        #expect(store.state.pendingStatusChange == pendingStatusChange)
        #expect(
            store.state.pendingProviderReset == pendingProviderReset
        )
    }

    @Test
    func resetWindowRejectsQueuedTransitionEffects() async {
        let tracks = IdentifiedArray(uniqueElements: makeTracks())
        let pendingPlaybackTransition = PendingPlaybackTransition(
            requestID: UUID(1),
            queue: tracks,
            targetTrackID: tracks[0].id
        )
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let resolveCalls = LockIsolated(0)
        let resource = makeResource(for: tracks[0].id)
        let store = makeStore(
            pendingPlaybackTransition: pendingPlaybackTransition,
            pendingProviderReset: pendingProviderReset
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resolveCalls.withValue { $0 += 1 }
                return resource
            }
        }

        await store.send(
            .resolveTransition(requestID: UUID(1), trackID: tracks[0].id)
        )
        await Task.yield()

        #expect(resolveCalls.value == 0)
        #expect(
            store.state.pendingPlaybackTransition == pendingPlaybackTransition
        )
    }

    @Test
    func resetWindowRejectsIneligibleSelectionPresentation() async {
        let tracks = IdentifiedArray(uniqueElements: makeTracks())
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: providerID,
            capabilities: .allEnabled
        )
        let store = makeStore(pendingProviderReset: pendingProviderReset)

        await store.send(
            .selectionReceived(
                tracks[0].id,
                loadedResults: tracks,
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

    // MARK: - Timeline

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
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: false,
            supportsQueueReplacement: true,
            supportsQueueTransitions: true,
            supportedRepeatModes: [.off, .all, .one],
            supportsShuffle: true
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
    func pendingTransitionTimelineIntentsAreTrueNoOps() async {
        let queue = makeQueue(duration: 180)
        let tracks = IdentifiedArray(uniqueElements: makeTracks())
        let store = makeStore(
            queue: queue,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: tracks,
                targetTrackID: tracks[0].id
            )
        )

        #expect(!store.state.canRequestSeek)
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

    // MARK: - Queue Transitions

    @Test
    func parentRoutesAuthorizedQueueTransitionsToTheQueueChild() async {
        let tracks = makeTracks()
        let confirmedQueue = IdentifiedArray(uniqueElements: tracks)
        let previousProbe = SuspendedOperationProbe<PlaybackResource>()
        let nextProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[1].id,
                repeatMode: .off,
                shuffleMode: .off
            )
        ) {
            $0.playbackResourceClients = self.makeResourceClients { trackID in
                if trackID == tracks[0].id {
                    return try await previousProbe.run()
                }
                return try await nextProbe.run()
            }
        }

        await store.send(.previousTapped)
        await store.receive(.queue(.previousTapped))
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[0].id)))
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: confirmedQueue,
                targetTrackID: tracks[0].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[0].id)
        )
        await previousProbe.waitUntilStarted()

        #expect(store.state.queue.currentTrackID == tracks[1].id)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await previousProbe.waitUntilCancelled()

        await store.send(.nextTapped)
        await store.receive(.queue(.nextTapped))
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[2].id)))
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: confirmedQueue,
                targetTrackID: tracks[2].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(1), trackID: tracks[2].id)
        )
        await nextProbe.waitUntilStarted()

        #expect(store.state.queue.currentTrackID == tracks[1].id)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await nextProbe.waitUntilCancelled()
    }

    @Test
    func queueBoundariesAndPendingTransitionsBlockQueueCommands() async {
        let tracks = makeTracks()
        let boundedStore = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[2].id,
                repeatMode: .off,
                shuffleMode: .off
            )
        )
        let transitioningStore = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[1].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: IdentifiedArray(uniqueElements: tracks),
                targetTrackID: tracks[0].id
            )
        )

        #expect(!boundedStore.state.canRequestNext)
        #expect(boundedStore.state.canRequestPrevious)
        #expect(!transitioningStore.state.canRequestNext)
        #expect(!transitioningStore.state.canRequestPrevious)
        await boundedStore.send(.nextTapped)
        await transitioningStore.send(.previousTapped)
    }

    @Test
    func providerSnapshotConfirmsTheCurrentTrack() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        )

        let snapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .playing,
            position: 0
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot))
        await store.receive(.queue(.currentTrackConfirmed(tracks[1].id))) {
            $0.queue.currentTrackID = tracks[1].id
        }
        await store.receive(.timeline(.positionObserved(0)))

        #expect(store.state.queue.currentTrack == tracks[1])
    }

    // MARK: - Player Observation

    @Test
    func waitingSnapshotForTheTargetCommitsTheFrozenQueue() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            failureNotice: PlaybackFailureNotice(
                trackID: nextSongs[1].id,
                failure: .playbackFailed
            ),
            timeline: .init(confirmedPosition: 42, interaction: .idle),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[1].id
            )
        )

        let snapshot = makeSnapshot(
            itemID: nextSongs[1].id,
            status: .waiting,
            position: 0,
            duration: 180
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.status = .waiting
            $0.failureNotice = nil
            $0.pendingPlaybackTransition = nil
        }
        await store.receive(
            .queue(.replace(nextResults, startingAt: nextSongs[1].id))
        ) {
            $0.queue.tracks = nextResults
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: Array(nextResults.ids)
            )
            $0.queue.currentTrackID = nextSongs[1].id
        }
        await store.receive(.timeline(.positionObserved(0))) {
            $0.timeline.confirmedPosition = 0
        }

        #expect(store.state.queue.currentTrack == nextSongs[1])
        #expect(store.state.pendingPlaybackTransition == nil)
    }

    @Test
    func targetConfirmationAppliesTheObservedPositionAndDuration() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore(
            timeline: .init(confirmedPosition: 99, interaction: .idle),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[2].id
            )
        )

        let snapshot = makeSnapshot(
            itemID: tracks[2].id,
            status: .playing,
            position: 12,
            duration: 180
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.status = .playing
            $0.pendingPlaybackTransition = nil
        }
        await store.receive(
            .queue(.replace(loadedResults, startingAt: tracks[2].id))
        ) {
            $0.queue.tracks = loadedResults
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: tracks.map(\.id)
            )
            $0.queue.currentTrackID = tracks[2].id
        }
        await store.receive(.timeline(.positionObserved(12))) {
            $0.timeline.confirmedPosition = 12
        }

        #expect(store.state.timeline.position == 12)
        #expect(store.state.queue.currentTrack?.duration == 180)
        #expect(store.state.canRequestSeek)
    }

    @Test
    func staleSnapshotCannotConfirmAnotherTransition() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let pending = PendingPlaybackTransition(
            requestID: UUID(0),
            queue: nextResults,
            targetTrackID: nextSongs[1].id
        )
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingPlaybackTransition: pending
        )

        let snapshot = makeSnapshot(
            itemID: confirmedSongs[0].id,
            status: .playing,
            position: 5
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot))
        await store.receive(
            .queue(.currentTrackConfirmed(confirmedSongs[0].id))
        )
        await store.receive(.timeline(.positionObserved(5))) {
            $0.timeline.confirmedPosition = 5
        }

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.pendingPlaybackTransition == pending)
    }

    @Test
    func runtimeFailureForThePendingTargetClearsOnlyThatTransition() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(confirmedQueue.ids)
                ),
                currentTrackID: confirmedSongs[1].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[0].id
            )
        )

        await store.send(
            .observationReceived(.failed(nextSongs[0].id, .preparationFailed))
        )
        await store.receive(
            .runtimePlaybackFailed(nextSongs[0].id, .preparationFailed)
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: nextSongs[0].id,
                failure: .preparationFailed
            )
            $0.pendingPlaybackTransition = nil
        }

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == confirmedSongs[1])
        #expect(store.state.status == .playing)
    }

    // MARK: - Automatic Completion

    @Test
    func completionForAStaleTrackIsIgnored() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        )

        await store.send(.observationReceived(.completed(tracks[2].id)))
        await store.receive(.currentTrackCompleted(tracks[2].id))

        #expect(store.state.pendingPlaybackTransition == nil)
        #expect(store.state.queue.currentTrackID == tracks[0].id)
    }

    @Test(
        arguments: [
            (PlaybackRepeatMode.off, 0, 1),
            (.all, 2, 0),
            (.one, 1, 1),
        ]
    )
    func matchingCompletionStartsTheTransitionQueuePolicyChose(
        repeatMode: PlaybackRepeatMode,
        currentIndex: Int,
        targetIndex: Int
    ) async {
        let tracks = makeTracks()
        let confirmedQueue = IdentifiedArray(uniqueElements: tracks)
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[currentIndex].id,
                repeatMode: repeatMode,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(
            .observationReceived(.completed(tracks[currentIndex].id))
        )
        await store.receive(.currentTrackCompleted(tracks[currentIndex].id))
        await store.receive(
            .queue(.currentTrackCompleted(tracks[currentIndex].id))
        )
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[targetIndex].id)))
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: confirmedQueue,
                targetTrackID: tracks[targetIndex].id
            )
        }
        await store.receive(
            .resolveTransition(
                requestID: UUID(0),
                trackID: tracks[targetIndex].id
            )
        )
        await probe.waitUntilStarted()

        #expect(store.state.queue.currentTrackID == tracks[currentIndex].id)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func completionAtTheEndWithRepeatOffStartsNoTransition() async {
        let tracks = makeTracks()
        let store = makeStore(
            queue: .init(
                tracks: IdentifiedArray(uniqueElements: tracks),
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[2].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        )

        await store.send(.observationReceived(.completed(tracks[2].id)))
        await store.receive(.currentTrackCompleted(tracks[2].id))
        await store.receive(.queue(.currentTrackCompleted(tracks[2].id)))

        #expect(store.state.pendingPlaybackTransition == nil)
    }

    @Test
    func automaticTransitionSupersedesAPendingStatusChange() async {
        let tracks = makeTracks()
        let confirmedQueue = IdentifiedArray(uniqueElements: tracks)
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingStatusChange: PlaybackFeature.PendingStatusChange(
                requestID: UUID(9),
                target: .paused
            )
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(.nextTapped)
        await store.receive(.queue(.nextTapped))
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[1].id)))
        ) {
            $0.pendingStatusChange = nil
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: confirmedQueue,
                targetTrackID: tracks[1].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[1].id)
        )
        await probe.waitUntilStarted()

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    // MARK: - Helpers

    private let providerID = ProviderID(rawValue: "fake")

    private func makeQueue(duration: TimeInterval?) -> PlaybackQueueFeature.State {
        let song = Track(
            id: TrackID(providerID: providerID, nativeID: "timeline"),
            title: "Timeline",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: duration
        )
        return PlaybackQueueFeature.State(
            tracks: IdentifiedArray(uniqueElements: [song]),
            playbackOrder: PlaybackQueueOrder(trackIDs: [song.id]),
            currentTrackID: song.id,
            repeatMode: .off,
            shuffleMode: .off
        )
    }

    private func makeStore(
        queue: PlaybackQueueFeature.State = .init(
            tracks: [],
            playbackOrder: PlaybackQueueOrder(trackIDs: []),
            currentTrackID: nil,
            repeatMode: .off,
            shuffleMode: .off
        ),
        status: PlaybackStatus = .idle,
        failureNotice: PlaybackFailureNotice? = nil,
        playbackEligibility: CatalogPlaybackEligibility = .unknown,
        capabilities: MusicProviderCapabilities = .allEnabled,
        timeline: PlaybackTimelineFeature.State = .init(
            confirmedPosition: 0,
            interaction: .idle
        ),
        pendingPlaybackTransition: PendingPlaybackTransition? = nil,
        pendingStatusChange: PlaybackFeature.PendingStatusChange? = nil,
        pendingProviderReset: PlaybackFeature.PendingProviderReset? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackFeature> {
        TestStore(
            initialState: PlaybackFeature.State(
                providerID: providerID,
                queue: queue,
                status: status,
                failureNotice: failureNotice,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities,
                timeline: timeline,
                pendingPlaybackTransition: pendingPlaybackTransition,
                pendingStatusChange: pendingStatusChange,
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

    private func makeResourceClients(
        resolve: @escaping @Sendable (TrackID) async throws -> PlaybackResource
    ) -> ProviderClientRegistry<PlaybackResourceClient> {
        ProviderClientRegistry(
            clients: [providerID: PlaybackResourceClient(resolve: resolve)]
        )
    }

    private func makeResource(for trackID: TrackID) -> PlaybackResource {
        PlaybackResource(
            trackID: trackID,
            location: .localFile(
                URL(fileURLWithPath: "/tmp/\(trackID.nativeID).m4a")
            )
        )
    }

    private func makeTracks(prefix: String = "song") -> [Track] {
        [
            makeTrack(nativeID: "\(prefix)-1"),
            makeTrack(nativeID: "\(prefix)-2"),
            makeTrack(nativeID: "\(prefix)-3"),
        ]
    }

    private func makeTrack(
        providerID: ProviderID = "fake",
        nativeID: String
    ) -> Track {
        Track(
            id: TrackID(providerID: providerID, nativeID: nativeID),
            title: nativeID,
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: 180
        )
    }

    private func makeSnapshot(
        itemID: TrackID?,
        status: PlaybackStatus,
        position: TimeInterval,
        duration: TimeInterval? = nil
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            currentTrackID: itemID,
            status: status,
            position: position,
            duration: duration
        )
    }
}
