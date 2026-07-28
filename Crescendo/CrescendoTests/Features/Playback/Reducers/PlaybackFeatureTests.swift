@preconcurrency import AVFoundation
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
                loadedResults: loadedResults
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[1].id)
        )
        await probe.waitUntilStarted()

        #expect(store.state.pendingPlaybackTransition?.queue == loadedResults)

        await cancelPlaybackTransition(in: store)
        await probe.waitUntilCancelled()
    }

    @Test
    func selectionRoutesTheTargetThroughItsOwnProvider() async {
        let jamendo = makeTrack(providerID: .jamendo, nativeID: "remote")
        let local = makeTrack(providerID: .localMusic, nativeID: "local")
        let loadedResults: IdentifiedArrayOf<Track> = [jamendo, local]
        let resolvedIDs = LockIsolated<[TrackID]>([])
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let jamendoResource = makeResource(for: jamendo.id)
        let store = makeStore {
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [
                    .jamendo: PlaybackResourceClient { _ in
                        Issue.record("The non-target provider must not resolve")
                        return jamendoResource
                    },
                    .localMusic: PlaybackResourceClient { trackID in
                        resolvedIDs.withValue { $0.append(trackID) }
                        return try await probe.run()
                    },
                ]
            )
        }

        await store.send(
            .selectionReceived(local.id, loadedResults: loadedResults)
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: local.id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: local.id)
        )
        await probe.waitUntilStarted()

        #expect(resolvedIDs.value == [local.id])

        await cancelPlaybackTransition(in: store)
        await probe.waitUntilCancelled()
    }

    @Test
    func laterLoadedResultsCannotMutateTheFrozenTransitionQueue() async {
        let firstPage = makeTracks(prefix: "first")
        var loadedResults = IdentifiedArray(uniqueElements: firstPage)
        let frozenResults = loadedResults
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(
            .selectionReceived(
                firstPage[0].id,
                loadedResults: loadedResults
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: frozenResults,
                targetTrackID: firstPage[0].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: firstPage[0].id)
        )
        await probe.waitUntilStarted()

        loadedResults.append(makeTrack(nativeID: "later"))

        #expect(store.state.pendingPlaybackTransition?.queue == frozenResults)

        await cancelPlaybackTransition(in: store)
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
                loadedResults: loadedResults
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[0].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[0].id)
        )
        await probe.waitUntilStarted()

        await cancelPlaybackTransition(in: store)
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
                loadedResults: nextResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[0].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: nextSongs[0].id)
        )
        await probe.waitUntilStarted()

        #expect(!store.state.isPlayerPresented)

        await cancelPlaybackTransition(in: store)
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
            duration: nil,
            isSeekable: false,
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
                loadedResults: nextResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[1].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: nextSongs[1].id)
        )
        await probe.waitUntilStarted()

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == confirmedSongs[0])
        #expect(store.state.status == .playing)
        #expect(store.state.timeline == timeline)

        await cancelPlaybackTransition(in: store)
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
            duration: nil,
            isSeekable: false,
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
            $0.playbackItem.load = { _, _ in try await probe.run() }
            $0.playbackItem.rollback = { _ in }
        }

        await store.send(
            .selectionReceived(
                nextSongs[1].id,
                loadedResults: nextResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[1].id
            )
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

        await cancelPlaybackTransition(in: store)
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
            $0.playbackItem.load = { _, _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
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
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
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
            $0.playbackItem.load = { loaded, _ in
                loadedResources.withValue { $0.append(loaded) }
            }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
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
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
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
            $0.playbackItem.load = { _, _ in
                calls.withValue { $0.append("load") }
            }
            $0.playbackTransport.play = {
                calls.withValue { $0.append("play") }
            }
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
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
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
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
            $0.playbackItem.load = { _, _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
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
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        #expect(store.state.queue.tracks.isEmpty)
        #expect(store.state.queue.currentTrackID == nil)
        #expect(store.state.status == .idle)
        #expect(store.state.timeline.confirmedPosition == 0)
        let expectedTransition = PendingPlaybackTransition(
            requestID: UUID(0),
            queue: loadedResults,
            targetTrackID: tracks[1].id,
            hasLoadedItem: true
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
            targetTrackID: tracks[1].id,
            hasLoadedItem: true
        )
        let snapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .playing,
            position: 7
        )
        let committedInstallations =
            LockIsolated<[PlaybackItemInstallation]>([])
        let store = makeStore(pendingPlaybackTransition: pending) {
            $0.playbackItem.commit = { installation in
                committedInstallations.withValue {
                    $0.append(installation)
                }
            }
        }

        #expect(committedInstallations.value.isEmpty)
        await store.send(.observationReceived(.snapshot(snapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: snapshot
        )
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
        await finishPendingCommit(in: store, settlement: settlement)

        #expect(store.state.queue.currentTrack == tracks[1])
        #expect(store.state.pendingPlaybackTransition == nil)
        #expect(
            committedInstallations.value
                == [PlaybackItemInstallation(id: UUID(0))]
        )
    }

    @Test
    func snapshotReconcilesConfirmedSeekability() async {
        let track = makeTrack(nativeID: "seekability")
        let queue = PlaybackQueueFeature.State(
            tracks: [track],
            playbackOrder: PlaybackQueueOrder(trackIDs: [track.id]),
            currentTrackID: track.id,
            repeatMode: .off,
            shuffleMode: .off
        )
        let store = makeStore(queue: queue)
        let snapshot = PlaybackSnapshot(
            currentTrackID: track.id,
            status: .paused,
            position: 0,
            duration: 180,
            isSeekable: true
        )

        await store.send(.reconcileSnapshot(snapshot)) {
            $0.status = .paused
            $0.timeline.duration = 180
            $0.timeline.isSeekable = true
        }
        await store.receive(.queue(.currentTrackConfirmed(track.id)))
        await store.receive(.timeline(.positionObserved(0)))

        #expect(store.state.canRequestSeek)
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
                loadedResults: firstResults
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: firstResults,
                targetTrackID: firstSongs[0].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: firstSongs[0].id)
        )
        await firstProbe.waitUntilStarted()

        await store.send(
            .selectionReceived(
                secondSongs[1].id,
                loadedResults: secondResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: secondResults,
                targetTrackID: secondSongs[1].id,
                settlement: .rollingBack(
                    .superseding(
                        PlaybackItemInstallation(id: UUID(0))
                    )
                )
            )
        }
        await firstProbe.waitUntilCancelled()
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(1))
        ) {
            $0.pendingPlaybackTransition?.settlement = .none
        }
        await store.receive(
            .resolveTransition(requestID: UUID(1), trackID: secondSongs[1].id)
        )
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

        await cancelPlaybackTransition(in: store)
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
            duration: nil,
            isSeekable: false,
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
            $0.playbackItem.load = { _, _ in
                throw PlaybackFailure.preparationFailed
            }
            $0.playbackTransport.play = {
                playCalls.withValue { $0 += 1 }
            }
        }

        await store.send(
            .selectionReceived(
                nextSongs[0].id,
                loadedResults: nextResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[0].id
            )
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
            $0.playbackItem.load = { _, _ in }
            $0.playbackItem.rollback = { _ in }
            $0.playbackTransport.play = {
                throw MusicProviderError.playbackFailed
            }
        }

        await store.send(
            .selectionReceived(
                nextSongs[0].id,
                loadedResults: nextResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[0].id
            )
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
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(
            .transitionPlayFailed(
                requestID: UUID(0),
                trackID: nextSongs[0].id,
                failure: .playbackFailed
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: nextSongs[0].id,
                failure: .playbackFailed
            )
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    PlaybackItemInstallation(id: UUID(0)),
                    followUp: .none
                )
            )
        }
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(0))
        ) {
            $0.pendingPlaybackTransition = nil
        }

        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == confirmedSongs[1])
        #expect(store.state.status == .playing)
    }

    @Test
    func liveInstalledItemRollsBackWhenTransportPlayFails() async throws {
        let confirmed = makeTrack(
            providerID: .localMusic,
            nativeID: "confirmed"
        )
        let target = makeTrack(providerID: .jamendo, nativeID: "target")
        let confirmedItem = AVPlayerItemFixture.make()
        let targetItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: confirmedItem)
        let registry = AVPlayerItemRegistry()
        registry.register(confirmedItem, trackID: confirmed.id)
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { _ in targetItem }
            ),
            registry: registry
        )
        let resource = try PlaybackResource(
            trackID: target.id,
            location: .progressive(
                #require(URL(string: "memory://target"))
            )
        )
        let confirmedQueue: IdentifiedArrayOf<Track> = [confirmed]
        let targetQueue: IdentifiedArrayOf<Track> = [target]
        let playProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [confirmed.id]
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [
                    .jamendo: PlaybackResourceClient { _ in resource }
                ]
            )
            $0.playbackItem = engine.item
            $0.playbackTransport.play = playProbe.run
        }

        await store.send(
            .selectionReceived(target.id, loadedResults: targetQueue)
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: targetQueue,
                targetTrackID: target.id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: target.id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await playProbe.waitUntilStarted()
        #expect(player.currentItem === targetItem)
        #expect(registry.trackID(for: targetItem) == target.id)

        playProbe.fail(with: PlaybackFailure.playbackFailed)
        await store.receive(
            .transitionPlayFailed(
                requestID: UUID(0),
                trackID: target.id,
                failure: .playbackFailed
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: target.id,
                failure: .playbackFailed
            )
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    PlaybackItemInstallation(id: UUID(0)),
                    followUp: .none
                )
            )
        }
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(0))
        ) {
            $0.pendingPlaybackTransition = nil
        }

        #expect(player.currentItem === confirmedItem)
        #expect(registry.trackID(for: confirmedItem) == confirmed.id)
        #expect(registry.trackID(for: targetItem) == nil)
        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrackID == confirmed.id)
    }

    @Test
    func cancellationBeforeItemLoadedAcknowledgementRestoresConfirmedItem()
        async throws
    {
        let confirmed = makeTrack(
            providerID: .localMusic,
            nativeID: "confirmed"
        )
        let target = makeTrack(providerID: .jamendo, nativeID: "target")
        let confirmedItem = AVPlayerItemFixture.make()
        let targetItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: confirmedItem)
        let registry = AVPlayerItemRegistry()
        registry.register(confirmedItem, trackID: confirmed.id)
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { _ in targetItem }
            ),
            registry: registry
        )
        let installation = PlaybackItemInstallation(id: UUID(0))
        let resource = try PlaybackResource(
            trackID: target.id,
            location: .progressive(
                #require(URL(string: "memory://target"))
            )
        )
        let confirmedQueue: IdentifiedArrayOf<Track> = [confirmed]
        let targetQueue: IdentifiedArrayOf<Track> = [target]
        let loadProbe = SuspendedOperationProbe<Void>()
        var itemClient = engine.item
        itemClient.load = { resource, installation in
            try await engine.item.load(resource, installation)
            try await loadProbe.run()
        }

        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [confirmed.id]
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [
                    .jamendo: PlaybackResourceClient { _ in resource }
                ]
            )
            $0.playbackItem = itemClient
        }

        await store.send(
            .selectionReceived(target.id, loadedResults: targetQueue)
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: targetQueue,
                targetTrackID: target.id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: target.id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await loadProbe.waitUntilStarted()

        #expect(player.currentItem === targetItem)
        #expect(registry.trackID(for: targetItem) == target.id)

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    installation,
                    followUp: .none
                )
            )
        }
        await loadProbe.waitUntilCancelled()
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(0))
        ) {
            $0.pendingPlaybackTransition = nil
        }

        #expect(player.currentItem === confirmedItem)
        #expect(registry.trackID(for: confirmedItem) == confirmed.id)
        #expect(registry.trackID(for: targetItem) == nil)
        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrackID == confirmed.id)
    }

    @Test
    func suspendedCommitSettlesBeforeFollowUpStartsAndBecomesItsRollbackBaseline()
        async throws
    {
        let confirmed = makeTrack(
            providerID: .localMusic,
            nativeID: "confirmed"
        )
        let firstTarget = makeTrack(
            providerID: .jamendo,
            nativeID: "first"
        )
        let followUpTarget = makeTrack(
            providerID: .jamendo,
            nativeID: "follow-up"
        )
        let confirmedItem = AVPlayerItemFixture.make()
        let firstTargetItem = AVPlayerItemFixture.make()
        let followUpItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: confirmedItem)
        let registry = AVPlayerItemRegistry()
        registry.register(confirmedItem, trackID: confirmed.id)
        let firstResource = try PlaybackResource(
            trackID: firstTarget.id,
            location: .progressive(
                #require(URL(string: "memory://first"))
            )
        )
        let followUpResource = try PlaybackResource(
            trackID: followUpTarget.id,
            location: .progressive(
                #require(URL(string: "memory://follow-up"))
            )
        )
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { asset in
                    asset.url == firstResource.location.url
                        ? firstTargetItem
                        : followUpItem
                }
            ),
            registry: registry
        )
        let firstInstallation = PlaybackItemInstallation(id: UUID(99))
        try await engine.item.load(firstResource, firstInstallation)
        #expect(player.currentItem === firstTargetItem)

        let commitProbe = SuspendedOperationProbe<Void>()
        var itemClient = engine.item
        itemClient.commit = { installation in
            do {
                try await commitProbe.run()
            } catch {
                return
            }
            await engine.item.commit(installation)
        }
        let confirmedQueue: IdentifiedArrayOf<Track> = [confirmed]
        let firstQueue: IdentifiedArrayOf<Track> = [firstTarget]
        let followUpQueue: IdentifiedArrayOf<Track> = [followUpTarget]
        let firstSnapshot = makeSnapshot(
            itemID: firstTarget.id,
            status: .waiting,
            position: 7,
            duration: 180,
            isSeekable: false
        )
        let commit = PendingPlaybackTransition.Commit(
            snapshot: firstSnapshot
        )
        let followUpIntent = PendingPlaybackTransition.TransitionIntent(
            requestID: UUID(0),
            queue: followUpQueue,
            targetTrackID: followUpTarget.id,
            origin: .selection
        )
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [confirmed.id]
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(99),
                queue: firstQueue,
                targetTrackID: firstTarget.id,
                hasLoadedItem: true
            )
        ) {
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [
                    .jamendo: PlaybackResourceClient { trackID in
                        #expect(trackID == followUpTarget.id)
                        return followUpResource
                    }
                ]
            )
            $0.playbackItem = itemClient
            $0.playbackTransport.play = {
                throw PlaybackFailure.playbackFailed
            }
        }

        await store.send(.observationReceived(.snapshot(firstSnapshot)))
        await store.receive(.reconcileSnapshot(firstSnapshot)) {
            $0.pendingPlaybackTransition?.settlement = .committing(commit)
        }
        await commitProbe.waitUntilStarted()

        await store.send(
            .selectionReceived(
                followUpTarget.id,
                loadedResults: followUpQueue
            )
        ) {
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(
                    snapshot: firstSnapshot,
                    followUp: .transition(followUpIntent)
                )
            )
        }
        #expect(player.currentItem === firstTargetItem)
        #expect(store.state.queue.currentTrackID == confirmed.id)

        commitProbe.succeed()
        await store.receive(
            .transitionCommitCompleted(
                requestID: UUID(99),
                installation: firstInstallation
            )
        ) {
            $0.status = .waiting
            $0.timeline.duration = 180
            $0.timeline.isSeekable = false
            $0.pendingPlaybackTransition?.settlement = .applyingCommit(
                PendingPlaybackTransition.Commit(
                    snapshot: firstSnapshot,
                    followUp: .transition(followUpIntent)
                )
            )
        }
        await store.receive(
            .queue(.replace(firstQueue, startingAt: firstTarget.id))
        ) {
            $0.queue.tracks = firstQueue
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: [firstTarget.id]
            )
            $0.queue.currentTrackID = firstTarget.id
        }
        await store.receive(.timeline(.positionObserved(7))) {
            $0.timeline.confirmedPosition = 7
        }
        await store.receive(
            .transitionConfirmationApplied(
                requestID: UUID(99),
                installation: firstInstallation
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: followUpQueue,
                targetTrackID: followUpTarget.id
            )
        }
        await store.receive(
            .resolveTransition(
                requestID: UUID(0),
                trackID: followUpTarget.id
            )
        )
        await store.receive(
            .transitionResourceResolved(
                requestID: UUID(0),
                resource: followUpResource
            )
        )
        await store.receive(
            .loadTransition(
                requestID: UUID(0),
                resource: followUpResource
            )
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(
            .transitionPlayFailed(
                requestID: UUID(0),
                trackID: followUpTarget.id,
                failure: .playbackFailed
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: followUpTarget.id,
                failure: .playbackFailed
            )
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    PlaybackItemInstallation(id: UUID(0)),
                    followUp: .none
                )
            )
        }
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(0))
        ) {
            $0.pendingPlaybackTransition = nil
        }

        #expect(player.currentItem === firstTargetItem)
        #expect(registry.trackID(for: firstTargetItem) == firstTarget.id)
        #expect(registry.trackID(for: confirmedItem) == nil)
        #expect(registry.trackID(for: followUpItem) == nil)
        #expect(store.state.queue.tracks == firstQueue)
        #expect(store.state.queue.currentTrackID == firstTarget.id)
        #expect(store.state.status == .waiting)
    }

    @Test
    func multipleCommitFollowUpsRetainOnlyTheLatestTransitionIntent() async {
        let confirmed = makeTrack(nativeID: "confirmed")
        let firstTarget = makeTrack(nativeID: "first")
        let selectedTarget = makeTrack(nativeID: "selected")
        let navigatedTarget = makeTrack(nativeID: "navigated")
        let confirmedQueue: IdentifiedArrayOf<Track> = [confirmed]
        let firstQueue: IdentifiedArrayOf<Track> = [
            firstTarget,
            selectedTarget,
            navigatedTarget,
        ]
        let selectedQueue: IdentifiedArrayOf<Track> = [selectedTarget]
        let snapshot = makeSnapshot(
            itemID: firstTarget.id,
            status: .waiting,
            position: 4
        )
        let commitProbe = SuspendedOperationProbe<Void>()
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [confirmed.id]
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(99),
                queue: firstQueue,
                targetTrackID: firstTarget.id,
                hasLoadedItem: true
            )
        ) {
            $0.playbackItem.commit = { _ in
                try? await commitProbe.run()
            }
            $0.playbackItem.rollback = { _ in }
            $0.playbackResourceClients = self.makeResourceClients { trackID in
                #expect(trackID == navigatedTarget.id)
                return try await resolveProbe.run()
            }
        }

        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(snapshot: snapshot)
            )
        }
        await commitProbe.waitUntilStarted()

        await store.send(
            .selectionReceived(
                selectedTarget.id,
                loadedResults: selectedQueue
            )
        ) {
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(
                    snapshot: snapshot,
                    followUp: .transition(
                        PendingPlaybackTransition.TransitionIntent(
                            requestID: UUID(0),
                            queue: selectedQueue,
                            targetTrackID: selectedTarget.id,
                            origin: .selection
                        )
                    )
                )
            )
        }
        await store.send(.stopTapped) {
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(1),
                target: .stopped
            )
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(
                    snapshot: snapshot,
                    followUp: .stop(requestID: UUID(1))
                )
            )
        }
        await store.send(
            .queue(
                .delegate(
                    .transitionRequested(navigatedTarget.id)
                )
            )
        ) {
            $0.pendingStatusChange = nil
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(
                    snapshot: snapshot,
                    followUp: .transition(
                        PendingPlaybackTransition.TransitionIntent(
                            requestID: UUID(2),
                            queue: firstQueue,
                            targetTrackID: navigatedTarget.id,
                            origin: .navigation
                        )
                    )
                )
            )
        }

        commitProbe.succeed()
        let installation = PlaybackItemInstallation(id: UUID(99))
        let settledCommit = PendingPlaybackTransition.Commit(
            snapshot: snapshot,
            followUp: .transition(
                PendingPlaybackTransition.TransitionIntent(
                    requestID: UUID(2),
                    queue: firstQueue,
                    targetTrackID: navigatedTarget.id,
                    origin: .navigation
                )
            )
        )
        await store.receive(
            .transitionCommitCompleted(
                requestID: UUID(99),
                installation: installation
            )
        ) {
            $0.status = .waiting
            $0.timeline.isSeekable = true
            $0.pendingPlaybackTransition?.settlement = .applyingCommit(
                settledCommit
            )
        }
        await store.receive(
            .queue(.replace(firstQueue, startingAt: firstTarget.id))
        ) {
            $0.queue.tracks = firstQueue
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: Array(firstQueue.ids)
            )
            $0.queue.currentTrackID = firstTarget.id
        }
        await store.receive(.timeline(.positionObserved(4))) {
            $0.timeline.confirmedPosition = 4
        }
        await store.receive(
            .transitionConfirmationApplied(
                requestID: UUID(99),
                installation: installation
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(2),
                queue: firstQueue,
                targetTrackID: navigatedTarget.id,
                origin: .navigation
            )
        }
        await store.receive(
            .resolveTransition(
                requestID: UUID(2),
                trackID: navigatedTarget.id
            )
        )
        await resolveProbe.waitUntilStarted()

        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    PlaybackItemInstallation(id: UUID(2)),
                    followUp: .none
                )
            )
        }
        await resolveProbe.waitUntilCancelled()
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(2))
        ) {
            $0.pendingPlaybackTransition = nil
        }
    }

    @Test
    func latestStopFollowUpWaitsForCommitAndReplacesQueuedTransition() async {
        let confirmed = makeTrack(nativeID: "confirmed")
        let firstTarget = makeTrack(nativeID: "first")
        let followUpTarget = makeTrack(nativeID: "follow-up")
        let confirmedQueue: IdentifiedArrayOf<Track> = [confirmed]
        let firstQueue: IdentifiedArrayOf<Track> = [firstTarget]
        let followUpQueue: IdentifiedArrayOf<Track> = [followUpTarget]
        let followUpResource = makeResource(for: followUpTarget.id)
        let snapshot = makeSnapshot(
            itemID: firstTarget.id,
            status: .waiting,
            position: 2
        )
        let commitProbe = SuspendedOperationProbe<Void>()
        let stopProbe = SuspendedOperationProbe<Void>()
        let resolvedIDs = LockIsolated<[TrackID]>([])
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [confirmed.id]
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(99),
                queue: firstQueue,
                targetTrackID: firstTarget.id,
                hasLoadedItem: true
            )
        ) {
            $0.playbackItem.commit = { _ in
                try? await commitProbe.run()
            }
            $0.playbackResourceClients = self.makeResourceClients { trackID in
                resolvedIDs.withValue { $0.append(trackID) }
                return followUpResource
            }
            $0.playbackTransport.stop = {
                try await stopProbe.run()
            }
            $0.playbackTimeline.seek = { _ in }
        }

        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(snapshot: snapshot)
            )
        }
        await commitProbe.waitUntilStarted()

        await store.send(
            .selectionReceived(
                followUpTarget.id,
                loadedResults: followUpQueue
            )
        ) {
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(
                    snapshot: snapshot,
                    followUp: .transition(
                        PendingPlaybackTransition.TransitionIntent(
                            requestID: UUID(0),
                            queue: followUpQueue,
                            targetTrackID: followUpTarget.id,
                            origin: .selection
                        )
                    )
                )
            )
        }
        await store.send(.stopTapped) {
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(1),
                target: .stopped
            )
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(
                    snapshot: snapshot,
                    followUp: .stop(requestID: UUID(1))
                )
            )
        }
        #expect(resolvedIDs.value.isEmpty)

        commitProbe.succeed()
        let installation = PlaybackItemInstallation(id: UUID(99))
        let settledCommit = PendingPlaybackTransition.Commit(
            snapshot: snapshot,
            followUp: .stop(requestID: UUID(1))
        )
        await store.receive(
            .transitionCommitCompleted(
                requestID: UUID(99),
                installation: installation
            )
        ) {
            $0.status = .waiting
            $0.timeline.isSeekable = true
            $0.pendingPlaybackTransition?.settlement = .applyingCommit(
                settledCommit
            )
        }
        await store.receive(
            .queue(.replace(firstQueue, startingAt: firstTarget.id))
        ) {
            $0.queue.tracks = firstQueue
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: [firstTarget.id]
            )
            $0.queue.currentTrackID = firstTarget.id
        }
        await store.receive(.timeline(.positionObserved(2))) {
            $0.timeline.confirmedPosition = 2
        }
        await store.receive(
            .transitionConfirmationApplied(
                requestID: UUID(99),
                installation: installation
            )
        ) {
            $0.pendingPlaybackTransition = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(1), target: .stopped)
        )
        await stopProbe.waitUntilStarted()
        #expect(resolvedIDs.value.isEmpty)

        stopProbe.succeed()
        await store.receive(.statusChangeSucceeded(requestID: UUID(1))) {
            $0.status = .stopped
            $0.pendingStatusChange = nil
        }
        await store.receive(.timeline(.resetPosition)) {
            $0.timeline.confirmedPosition = 0
        }
    }

    @Test
    func staleCommitCompletionCannotSettleOrLaunchOverNewerTransition() async {
        let newerTarget = makeTrack(nativeID: "newer")
        let newerQueue: IdentifiedArrayOf<Track> = [newerTarget]
        let pending = PendingPlaybackTransition(
            requestID: UUID(1),
            queue: newerQueue,
            targetTrackID: newerTarget.id
        )
        let newerResource = makeResource(for: newerTarget.id)
        let resolvedIDs = LockIsolated<[TrackID]>([])
        let store = makeStore(pendingPlaybackTransition: pending) {
            $0.playbackResourceClients = self.makeResourceClients { trackID in
                resolvedIDs.withValue { $0.append(trackID) }
                return newerResource
            }
        }
        let staleInstallation = PlaybackItemInstallation(id: UUID(0))

        await store.send(
            .transitionCommitCompleted(
                requestID: UUID(0),
                installation: staleInstallation
            )
        )
        await store.send(
            .transitionConfirmationApplied(
                requestID: UUID(0),
                installation: staleInstallation
            )
        )

        #expect(store.state.pendingPlaybackTransition == pending)
        #expect(resolvedIDs.value.isEmpty)
    }

    @Test
    func newestMatchingSnapshotWinsWhileCommitIsSuspended() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let target = tracks[1]
        let firstSnapshot = makeSnapshot(
            itemID: target.id,
            status: .waiting,
            position: 2,
            duration: 100,
            isSeekable: false
        )
        let latestSnapshot = makeSnapshot(
            itemID: target.id,
            status: .playing,
            position: 9,
            duration: 120,
            isSeekable: true
        )
        let commitProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: queue,
                targetTrackID: target.id,
                hasLoadedItem: true
            )
        ) {
            $0.playbackItem.commit = { _ in
                try? await commitProbe.run()
            }
        }

        await store.send(.observationReceived(.snapshot(firstSnapshot)))
        await store.receive(.reconcileSnapshot(firstSnapshot)) {
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(
                    snapshot: firstSnapshot
                )
            )
        }
        await commitProbe.waitUntilStarted()

        await store.send(.observationReceived(.snapshot(latestSnapshot)))
        await store.receive(.reconcileSnapshot(latestSnapshot)) {
            $0.pendingPlaybackTransition?.settlement = .committing(
                PendingPlaybackTransition.Commit(
                    snapshot: latestSnapshot
                )
            )
        }

        commitProbe.succeed()
        let installation = PlaybackItemInstallation(id: UUID(0))
        await store.receive(
            .transitionCommitCompleted(
                requestID: UUID(0),
                installation: installation
            )
        ) {
            $0.status = .playing
            $0.timeline.duration = 120
            $0.timeline.isSeekable = true
            $0.pendingPlaybackTransition?.settlement = .applyingCommit(
                PendingPlaybackTransition.Commit(
                    snapshot: latestSnapshot
                )
            )
        }
        await store.receive(.queue(.replace(queue, startingAt: target.id))) {
            $0.queue.tracks = queue
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: tracks.map(\.id)
            )
            $0.queue.currentTrackID = target.id
        }
        await store.receive(.timeline(.positionObserved(9))) {
            $0.timeline.confirmedPosition = 9
        }
        await store.receive(
            .transitionConfirmationApplied(
                requestID: UUID(0),
                installation: installation
            )
        ) {
            $0.pendingPlaybackTransition = nil
        }
    }

    @Test
    func newestMatchingSnapshotWinsWhileCommitApplicationIsPending() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let target = tracks[1]
        let firstSnapshot = makeSnapshot(
            itemID: target.id,
            status: .waiting,
            position: 2,
            duration: 100,
            isSeekable: false
        )
        let latestSnapshot = makeSnapshot(
            itemID: target.id,
            status: .playing,
            position: 9,
            duration: 120,
            isSeekable: true
        )
        let installation = PlaybackItemInstallation(id: UUID(0))
        let store = makeStore(
            status: .waiting,
            timeline: PlaybackTimelineFeature.State(
                confirmedPosition: 2,
                duration: 100,
                isSeekable: false,
                interaction: .idle
            ),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: queue,
                targetTrackID: target.id,
                hasLoadedItem: true,
                settlement: .applyingCommit(
                    PendingPlaybackTransition.Commit(
                        snapshot: firstSnapshot
                    )
                )
            )
        )

        await store.send(.reconcileSnapshot(latestSnapshot)) {
            $0.pendingPlaybackTransition?.settlement = .applyingCommit(
                PendingPlaybackTransition.Commit(
                    snapshot: latestSnapshot
                )
            )
        }
        await store.send(
            .transitionConfirmationApplied(
                requestID: UUID(0),
                installation: installation
            )
        ) {
            $0.status = .playing
            $0.timeline.confirmedPosition = 9
            $0.timeline.duration = 120
            $0.timeline.isSeekable = true
            $0.pendingPlaybackTransition = nil
        }
    }

    @Test
    func staleSnapshotIsIgnoredWhileCommitApplicationIsPending() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let staleTrack = tracks[0]
        let target = tracks[1]
        let targetSnapshot = makeSnapshot(
            itemID: target.id,
            status: .playing,
            position: 9,
            duration: 120,
            isSeekable: true
        )
        let staleSnapshot = makeSnapshot(
            itemID: staleTrack.id,
            status: .paused,
            position: 2,
            duration: 100,
            isSeekable: false
        )
        let staleSnapshotWithoutIdentity = makeSnapshot(
            itemID: nil,
            status: .waiting,
            position: 3,
            duration: 101,
            isSeekable: false
        )
        let installation = PlaybackItemInstallation(id: UUID(0))
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: queue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: tracks.map(\.id)
                ),
                currentTrackID: target.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            timeline: PlaybackTimelineFeature.State(
                confirmedPosition: 9,
                duration: 120,
                isSeekable: true,
                interaction: .idle
            ),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: queue,
                targetTrackID: target.id,
                origin: .navigation,
                hasLoadedItem: true,
                settlement: .applyingCommit(
                    PendingPlaybackTransition.Commit(
                        snapshot: targetSnapshot
                    )
                )
            )
        )

        await store.send(.reconcileSnapshot(staleSnapshot))
        await store.send(.reconcileSnapshot(staleSnapshotWithoutIdentity))
        await store.send(
            .transitionConfirmationApplied(
                requestID: UUID(0),
                installation: installation
            )
        ) {
            $0.pendingPlaybackTransition = nil
        }

        #expect(store.state.queue.currentTrackID == target.id)
        #expect(store.state.status == targetSnapshot.status)
        #expect(
            store.state.timeline.confirmedPosition
                == targetSnapshot.position
        )
        #expect(store.state.timeline.duration == targetSnapshot.duration)
        #expect(
            store.state.timeline.isSeekable
                == targetSnapshot.isSeekable
        )
    }

    @Test
    func staleSnapshotWithoutIdentityIsIgnoredWhileCommitIsSuspended() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let confirmed = tracks[0]
        let target = tracks[1]
        let targetSnapshot = makeSnapshot(
            itemID: target.id,
            status: .playing,
            position: 9,
            duration: 120,
            isSeekable: true
        )
        let staleSnapshot = makeSnapshot(
            itemID: nil,
            status: .paused,
            position: 2,
            duration: 100,
            isSeekable: false
        )
        let installation = PlaybackItemInstallation(id: UUID(0))
        let commit = PendingPlaybackTransition.Commit(
            snapshot: targetSnapshot
        )
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: queue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: tracks.map(\.id)
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: queue,
                targetTrackID: target.id,
                origin: .navigation,
                hasLoadedItem: true,
                settlement: .committing(commit)
            )
        )

        await store.send(.reconcileSnapshot(staleSnapshot))
        await store.send(
            .transitionCommitCompleted(
                requestID: UUID(0),
                installation: installation
            )
        ) {
            $0.status = .playing
            $0.timeline.duration = 120
            $0.timeline.isSeekable = true
            $0.pendingPlaybackTransition?.settlement =
                .applyingCommit(commit)
        }
        await store.receive(.queue(.currentTrackConfirmed(target.id))) {
            $0.queue.currentTrackID = target.id
        }
        await store.receive(.timeline(.positionObserved(9))) {
            $0.timeline.confirmedPosition = 9
        }
        await store.receive(
            .transitionConfirmationApplied(
                requestID: UUID(0),
                installation: installation
            )
        ) {
            $0.pendingPlaybackTransition = nil
        }

        #expect(store.state.queue.currentTrackID == target.id)
        #expect(store.state.status == targetSnapshot.status)
        #expect(
            store.state.timeline.confirmedPosition
                == targetSnapshot.position
        )
        #expect(store.state.timeline.duration == targetSnapshot.duration)
        #expect(
            store.state.timeline.isSeekable
                == targetSnapshot.isSeekable
        )
    }

    @Test
    func supersedingAnInstalledTargetRestoresConfirmedItemBeforeResolvingNext()
        async throws
    {
        let confirmed = makeTrack(nativeID: "confirmed")
        let firstTarget = makeTrack(nativeID: "first-target")
        let secondTarget = makeTrack(nativeID: "second-target")
        let confirmedItem = AVPlayerItemFixture.make()
        let firstTargetItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: confirmedItem)
        let registry = AVPlayerItemRegistry()
        registry.register(confirmedItem, trackID: confirmed.id)
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { _ in firstTargetItem }
            ),
            registry: registry
        )
        let firstResource = makeResource(for: firstTarget.id)
        let secondResolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let playProbe = SuspendedOperationProbe<Void>()
        let confirmedQueue: IdentifiedArrayOf<Track> = [confirmed]
        let firstResults: IdentifiedArrayOf<Track> = [firstTarget]
        let secondResults: IdentifiedArrayOf<Track> = [secondTarget]
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [confirmed.id]
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { trackID in
                if trackID == firstTarget.id {
                    return firstResource
                }
                return try await secondResolveProbe.run()
            }
            $0.playbackItem = engine.item
            $0.playbackTransport.play = playProbe.run
        }

        await store.send(
            .selectionReceived(
                firstTarget.id,
                loadedResults: firstResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: firstResults,
                targetTrackID: firstTarget.id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: firstTarget.id)
        )
        await store.receive(
            .transitionResourceResolved(
                requestID: UUID(0),
                resource: firstResource
            )
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: firstResource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await playProbe.waitUntilStarted()
        #expect(player.currentItem === firstTargetItem)

        await store.send(
            .selectionReceived(
                secondTarget.id,
                loadedResults: secondResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: secondResults,
                targetTrackID: secondTarget.id,
                settlement: .rollingBack(
                    .superseding(
                        PlaybackItemInstallation(id: UUID(0))
                    )
                )
            )
        }
        await playProbe.waitUntilCancelled()
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(1))
        ) {
            $0.pendingPlaybackTransition?.settlement = .none
        }
        await store.receive(
            .resolveTransition(requestID: UUID(1), trackID: secondTarget.id)
        )
        await secondResolveProbe.waitUntilStarted()

        #expect(player.currentItem === confirmedItem)
        #expect(registry.trackID(for: confirmedItem) == confirmed.id)
        #expect(registry.trackID(for: firstTargetItem) == nil)

        await cancelPlaybackTransition(in: store)
        await secondResolveProbe.waitUntilCancelled()
    }

    @Test
    func stopRestoresInstalledTargetBeforeStartingTransportStop() async throws {
        let confirmed = makeTrack(nativeID: "confirmed")
        let target = makeTrack(nativeID: "target")
        let confirmedItem = AVPlayerItemFixture.make()
        let targetItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: confirmedItem)
        let registry = AVPlayerItemRegistry()
        registry.register(confirmedItem, trackID: confirmed.id)
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { _ in targetItem }
            ),
            registry: registry
        )
        let resource = makeResource(for: target.id)
        let playProbe = SuspendedOperationProbe<Void>()
        let stopProbe = SuspendedOperationProbe<Void>()
        let confirmedQueue: IdentifiedArrayOf<Track> = [confirmed]
        let targetResults: IdentifiedArrayOf<Track> = [target]
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [confirmed.id]
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem = engine.item
            $0.playbackTransport.play = playProbe.run
            $0.playbackTransport.stop = {
                #expect(player.currentItem === confirmedItem)
                try await stopProbe.run()
            }
        }

        await store.send(
            .selectionReceived(target.id, loadedResults: targetResults)
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: targetResults,
                targetTrackID: target.id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: target.id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await playProbe.waitUntilStarted()

        await store.send(.stopTapped) {
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    PlaybackItemInstallation(id: UUID(0)),
                    followUp: .stop(requestID: UUID(1))
                )
            )
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(1),
                target: .stopped
            )
        }
        await playProbe.waitUntilCancelled()
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(0))
        ) {
            $0.pendingPlaybackTransition = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(1), target: .stopped)
        )
        await stopProbe.waitUntilStarted()

        #expect(player.currentItem === confirmedItem)
        #expect(registry.trackID(for: confirmedItem) == confirmed.id)
        #expect(registry.trackID(for: targetItem) == nil)

        stopProbe.fail(with: PlaybackFailure.playbackFailed)
        await store.receive(
            .statusChangeFailed(
                requestID: UUID(1),
                error: .playbackFailed
            )
        ) {
            $0.pendingStatusChange = nil
            $0.failureNotice = PlaybackFailureNotice(
                trackID: confirmed.id,
                failure: .playbackFailed
            )
        }
    }

    @Test
    func playFailureAfterIdentityConfirmationStillSurfacesTheFailure() async throws {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[1].id)
        let playProbe = SuspendedOperationProbe<Void>()
        let rolledBackInstallations =
            LockIsolated<[PlaybackItemInstallation]>([])
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in }
            $0.playbackItem.commit = { _ in }
            $0.playbackItem.rollback = { installation in
                rolledBackInstallations.withValue {
                    $0.append(installation)
                }
            }
            $0.playbackTransport.play = {
                try await playProbe.run()
            }
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: queue
            )
        ) {
            $0.isPlayerPresented = true
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: queue,
                targetTrackID: tracks[1].id
            )
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
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await playProbe.waitUntilStarted()

        let snapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .waiting,
            position: 0,
            isSeekable: false
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: snapshot
        )
        await store.receive(.queue(.replace(queue, startingAt: tracks[1].id))) {
            $0.queue.tracks = queue
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: tracks.map(\.id)
            )
            $0.queue.currentTrackID = tracks[1].id
        }
        await store.receive(.timeline(.positionObserved(0)))
        await finishPendingCommit(in: store, settlement: settlement)

        try #require(!playProbe.hasObservedCancellation)
        playProbe.fail(with: PlaybackFailure.playbackFailed)
        await store.receive(
            .transitionPlayFailed(
                requestID: UUID(0),
                trackID: tracks[1].id,
                failure: .playbackFailed
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: tracks[1].id,
                failure: .playbackFailed
            )
        }
        #expect(rolledBackInstallations.value.isEmpty)
    }

    @Test
    func playFailureDuringCommitKeepsTheConfirmedTargetInstalled() async throws {
        let confirmed = makeTrack(
            providerID: .localMusic,
            nativeID: "confirmed"
        )
        let target = makeTrack(providerID: .jamendo, nativeID: "target")
        let confirmedItem = AVPlayerItemFixture.make()
        let targetItem = AVPlayerItemFixture.make()
        let player = AVPlayer(playerItem: confirmedItem)
        let registry = AVPlayerItemRegistry()
        registry.register(confirmedItem, trackID: confirmed.id)
        let resource = try PlaybackResource(
            trackID: target.id,
            location: .progressive(
                #require(URL(string: "memory://target"))
            )
        )
        let engine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: AVPlayerItemPreparer(
                loadIsPlayable: { _ in true },
                makeItem: { _ in targetItem }
            ),
            registry: registry
        )
        let playProbe = SuspendedOperationProbe<Void>()
        let commitProbe = SuspendedOperationProbe<Void>()
        var itemClient = engine.item
        itemClient.commit = { installation in
            do {
                try await commitProbe.run()
            } catch {
                return
            }
            await engine.item.commit(installation)
        }
        let confirmedQueue: IdentifiedArrayOf<Track> = [confirmed]
        let targetQueue: IdentifiedArrayOf<Track> = [target]
        let store = makeStore(
            queue: PlaybackQueueFeature.State(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [confirmed.id]
                ),
                currentTrackID: confirmed.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [
                    .jamendo: PlaybackResourceClient { _ in resource }
                ]
            )
            $0.playbackItem = itemClient
            $0.playbackTransport.play = playProbe.run
        }

        await store.send(
            .selectionReceived(target.id, loadedResults: targetQueue)
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: targetQueue,
                targetTrackID: target.id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: target.id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await playProbe.waitUntilStarted()

        let snapshot = makeSnapshot(
            itemID: target.id,
            status: .waiting,
            position: 3,
            duration: 180,
            isSeekable: false
        )
        let commit = PendingPlaybackTransition.Commit(snapshot: snapshot)
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.pendingPlaybackTransition?.settlement = .committing(commit)
        }
        await commitProbe.waitUntilStarted()

        playProbe.fail(with: PlaybackFailure.playbackFailed)
        await store.receive(
            .transitionPlayFailed(
                requestID: UUID(0),
                trackID: target.id,
                failure: .playbackFailed
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: target.id,
                failure: .playbackFailed
            )
        }
        #expect(player.currentItem === targetItem)
        #expect(registry.trackID(for: targetItem) == target.id)
        #expect(registry.trackID(for: confirmedItem) == confirmed.id)

        commitProbe.succeed()
        let installation = PlaybackItemInstallation(id: UUID(0))
        await store.receive(
            .transitionCommitCompleted(
                requestID: UUID(0),
                installation: installation
            )
        ) {
            $0.status = .waiting
            $0.timeline.duration = 180
            $0.timeline.isSeekable = false
            $0.pendingPlaybackTransition?.settlement =
                .applyingCommit(commit)
        }
        await store.receive(
            .queue(.replace(targetQueue, startingAt: target.id))
        ) {
            $0.queue.tracks = targetQueue
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: [target.id]
            )
            $0.queue.currentTrackID = target.id
        }
        await store.receive(.timeline(.positionObserved(3))) {
            $0.timeline.confirmedPosition = 3
        }
        await store.receive(
            .transitionConfirmationApplied(
                requestID: UUID(0),
                installation: installation
            )
        ) {
            $0.pendingPlaybackTransition = nil
        }

        #expect(player.currentItem === targetItem)
        #expect(registry.trackID(for: targetItem) == target.id)
        #expect(registry.trackID(for: confirmedItem) == nil)
        #expect(store.state.queue.currentTrackID == target.id)
        #expect(
            store.state.failureNotice
                == PlaybackFailureNotice(
                    trackID: target.id,
                    failure: .playbackFailed
                )
        )
    }

    @Test
    func missingTargetProviderPreservesConfirmedPlayback() async {
        let confirmed = makeTrack(providerID: .jamendo, nativeID: "confirmed")
        let target = makeTrack(providerID: .localMusic, nativeID: "target")
        let queue = PlaybackQueueFeature.State(
            tracks: [confirmed],
            playbackOrder: PlaybackQueueOrder(trackIDs: [confirmed.id]),
            currentTrackID: confirmed.id,
            repeatMode: .off,
            shuffleMode: .off
        )
        let store = makeStore(queue: queue) {
            $0.playbackResourceClients = ProviderClientRegistry(clients: [:])
        }

        await store.send(
            .selectionReceived(target.id, loadedResults: [target])
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: [target],
                targetTrackID: target.id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: target.id)
        )
        await store.receive(
            .transitionResolutionFailed(
                requestID: UUID(0),
                failure: .resourceUnavailable
            )
        ) {
            $0.failureNotice = PlaybackFailureNotice(
                trackID: target.id,
                failure: .resourceUnavailable
            )
            $0.pendingPlaybackTransition = nil
        }

        #expect(store.state.queue.currentTrackID == confirmed.id)
    }

    @Test
    func selectionForMissingTrackNeverStartsATransition() async {
        let resolveCalls = LockIsolated(0)
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[0].id)
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resolveCalls.withValue { $0 += 1 }
                return resource
            }
        }

        await store.send(
            .selectionReceived(
                TrackID(providerID: providerID, nativeID: "missing"),
                loadedResults: queue
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
                loadedResults: replacement
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: replacement,
                targetTrackID: replacement[0].id
            )
            $0.pendingStatusChange = nil
        }
        await store.receive(
            .resolveTransition(requestID: UUID(1), trackID: replacement[0].id)
        )
        await statusProbe.waitUntilCancelled()
        await resolveProbe.waitUntilStarted()

        #expect(statusProbe.hasObservedCancellation)
        #expect(store.state.pendingStatusChange == nil)

        await cancelPlaybackTransition(in: store)
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
                loadedResults: replacement
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: replacement,
                targetTrackID: replacement[0].id
            )
            $0.pendingStatusChange = nil
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
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.timeline.isSeekable = true
        }
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
            $0.playbackTransport.stop = stopProbe.run
        }

        await store.send(
            .selectionReceived(
                replacement[0].id,
                loadedResults: replacement
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: replacement,
                targetTrackID: replacement[0].id
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: replacement[0].id)
        )
        await resolveProbe.waitUntilStarted()

        #expect(store.state.canRequestStop)
        await store.send(.stopTapped) {
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    PlaybackItemInstallation(id: UUID(0)),
                    followUp: .stop(requestID: UUID(1))
                )
            )
            $0.pendingStatusChange = PlaybackFeature.PendingStatusChange(
                requestID: UUID(1),
                target: .stopped
            )
        }
        await resolveProbe.waitUntilCancelled()
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(0))
        ) {
            $0.pendingPlaybackTransition = nil
        }
        await store.receive(
            .performStatusChange(requestID: UUID(1), target: .stopped)
        )
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
            $0.timeline.isSeekable = true
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
    func stopTappedStopsThenSeeksToZeroInOrder() async {
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
            $0.playbackTransport.stop = {
                calls.withValue { $0.append("stop") }
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
        await store.receive(.timeline(.resetPosition))

        #expect(calls.value == ["stop", "seek:0.0"])
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
            $0.timeline.isSeekable = true
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
            timeline: .init(
                confirmedPosition: 4,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            ),
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
            $0.timeline.isSeekable = true
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
                duration: nil,
                isSeekable: false,
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
            $0.timeline.isSeekable = true
        }
        await store.receive(.timeline(.resetPosition)) {
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
            duration: nil,
            isSeekable: false,
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
                duration: nil,
                isSeekable: false,
                interaction: .dragging(position: 50)
            )
        ) {
            $0.playbackTransport.stop = {}
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
        await store.receive(.timeline(.resetPosition)) {
            $0.timeline.confirmedPosition = 0
            $0.timeline.interaction = .idle
        }
    }

    @Test(arguments: [TimeInterval?(180), TimeInterval?.none])
    func stopPreservesObservedDurationWhenCatalogDurationIsInaccurateOrMissing(
        catalogDuration: TimeInterval?
    ) async throws {
        let queue = makeQueue(duration: catalogDuration)
        let trackID = try #require(queue.currentTrackID)
        let stopProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: queue,
            status: .playing,
            timeline: .init(
                confirmedPosition: 42,
                duration: nil,
                isSeekable: false,
                interaction: .dragging(position: 50)
            )
        ) {
            $0.playbackTransport.stop = {}
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

        let snapshot = makeSnapshot(
            itemID: trackID,
            status: .paused,
            position: 0,
            duration: 120
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.status = .paused
            $0.timeline.duration = 120
            $0.timeline.isSeekable = true
        }
        await store.receive(.queue(.currentTrackConfirmed(trackID)))
        await store.receive(.timeline(.positionObserved(0))) {
            $0.timeline.confirmedPosition = 0
        }

        stopProbe.succeed()
        await store.receive(.statusChangeSucceeded(requestID: UUID(0))) {
            $0.status = .stopped
            $0.pendingStatusChange = nil
        }
        await store.receive(.timeline(.resetPosition)) {
            $0.timeline.interaction = .idle
        }

        #expect(store.state.timeline.duration == 120)
        #expect(store.state.timelineDuration == 120)
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
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.timeline.isSeekable = true
        }
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
            $0.timeline.isSeekable = true
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
            queue: .init(
                tracks: tracks,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(tracks.ids)),
                currentTrackID: tracks[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            failureNotice: nil,
            timeline: .init(
                confirmedPosition: 0,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            ),
            pendingPlaybackTransition: nil,
            pendingStatusChange: nil,
            isPlayerPresented: false
        )
        let transitioning = PlaybackFeature.State(
            queue: .init(
                tracks: [],
                playbackOrder: PlaybackQueueOrder(trackIDs: []),
                currentTrackID: nil,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .stopped,
            failureNotice: nil,
            timeline: .init(
                confirmedPosition: 0,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            ),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: tracks,
                targetTrackID: tracks[0].id
            ),
            pendingStatusChange: nil,
            isPlayerPresented: false
        )

        #expect(active.canRequestPlayPause)
        #expect(active.canRequestStop)
        #expect(!transitioning.canRequestPlayPause)
        #expect(!transitioning.canRequestStop)
    }

    // MARK: - Timeline

    @Test(arguments: [TimeInterval?(180), TimeInterval?.none])
    func observedDurationControlsSeekBoundsWhenCatalogDurationDiffersOrIsMissing(
        catalogDuration: TimeInterval?
    ) async throws {
        let queue = makeQueue(duration: catalogDuration)
        let trackID = try #require(queue.currentTrackID)
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let store = makeStore(
            queue: queue,
            status: .playing,
            timeline: .init(
                confirmedPosition: 110,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            )
        ) {
            $0.playbackTimeline.seek = { position in
                seekPositions.withValue { $0.append(position) }
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(
            .reconcileSnapshot(
                makeSnapshot(
                    itemID: trackID,
                    status: .playing,
                    position: 110,
                    duration: 120
                )
            )
        )
        await store.send(.seekForwardTapped)
        await store.finish()

        #expect(seekPositions.value == [120])
    }

    @Test
    func continuousTimelineIntentIsClampedByTheParent() async {
        let store = makeStore(
            queue: makeQueue(duration: 180),
            timeline: .init(
                confirmedPosition: 0,
                duration: 180,
                isSeekable: true,
                interaction: .idle
            )
        )

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
                duration: 180,
                isSeekable: true,
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
                duration: 180,
                isSeekable: true,
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
                duration: 180,
                isSeekable: true,
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
            timeline: .init(
                confirmedPosition: 175,
                duration: 180,
                isSeekable: true,
                interaction: .idle
            )
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
    func nonseekableTimelineIntentIsATrueNoOp() async {
        let store = makeStore(
            queue: makeQueue(duration: 180),
            timeline: .init(
                confirmedPosition: 0,
                duration: 180,
                isSeekable: false,
                interaction: .idle
            )
        )

        await store.send(.timelinePositionChanged(30))
        await store.send(.timelineInteractionEnded)
        await store.send(.restartTapped)
        await store.send(.seekBackwardTapped)
        await store.send(.seekForwardTapped)
    }

    @Test
    func missingDurationTimelineIntentsAreTrueNoOps() async {
        let store = makeStore(
            queue: makeQueue(duration: 180),
            timeline: .init(
                confirmedPosition: 0,
                duration: nil,
                isSeekable: true,
                interaction: .idle
            )
        )

        await store.send(.timelinePositionChanged(30))
        await store.send(.timelineInteractionEnded)
        await store.send(.restartTapped)
        await store.send(.seekBackwardTapped)
        await store.send(.seekForwardTapped)
    }

    @Test
    func nonpositiveDurationTimelineIntentsAreTrueNoOps() async {
        let store = makeStore(
            queue: makeQueue(duration: 180),
            timeline: .init(
                confirmedPosition: 0,
                duration: 0,
                isSeekable: true,
                interaction: .idle
            )
        )

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
            timeline: .init(
                confirmedPosition: 0,
                duration: 180,
                isSeekable: true,
                interaction: .idle
            ),
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
                targetTrackID: tracks[0].id,
                origin: .navigation
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[0].id)
        )
        await previousProbe.waitUntilStarted()

        #expect(store.state.queue.currentTrackID == tracks[1].id)

        await cancelPlaybackTransition(in: store)
        await previousProbe.waitUntilCancelled()

        await store.send(.nextTapped)
        await store.receive(.queue(.nextTapped))
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[2].id)))
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: confirmedQueue,
                targetTrackID: tracks[2].id,
                origin: .navigation
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(1), trackID: tracks[2].id)
        )
        await nextProbe.waitUntilStarted()

        #expect(store.state.queue.currentTrackID == tracks[1].id)

        await cancelPlaybackTransition(in: store)
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
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.timeline.isSeekable = true
        }
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
            timeline: .init(
                confirmedPosition: 42,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            ),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[1].id,
                hasLoadedItem: true
            )
        ) {
            $0.playbackItem.commit = { _ in }
        }

        let snapshot = makeSnapshot(
            itemID: nextSongs[1].id,
            status: .waiting,
            position: 0,
            duration: 180,
            isSeekable: false
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: snapshot
        )
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
        await finishPendingCommit(in: store, settlement: settlement)

        #expect(store.state.queue.currentTrack == nextSongs[1])
        #expect(store.state.pendingPlaybackTransition == nil)
    }

    @Test
    func targetConfirmationAppliesTheObservedPositionAndDuration() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore(
            timeline: .init(
                confirmedPosition: 99,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            ),
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[2].id,
                hasLoadedItem: true
            )
        ) {
            $0.playbackItem.commit = { _ in }
        }

        let snapshot = makeSnapshot(
            itemID: tracks[2].id,
            status: .playing,
            position: 12,
            duration: 180
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: snapshot
        )
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
        await finishPendingCommit(in: store, settlement: settlement)

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
            targetTrackID: nextSongs[1].id,
            hasLoadedItem: true
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
        await store.receive(.reconcileSnapshot(snapshot)) {
            $0.timeline.isSeekable = true
        }
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
        let rolledBackInstallations =
            LockIsolated<[PlaybackItemInstallation]>([])
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
                targetTrackID: nextSongs[0].id,
                hasLoadedItem: true
            )
        ) {
            $0.playbackItem.rollback = { installation in
                rolledBackInstallations.withValue {
                    $0.append(installation)
                }
            }
        }

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
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    PlaybackItemInstallation(id: UUID(0)),
                    followUp: .none
                )
            )
        }
        await store.receive(
            .transitionRollbackCompleted(requestID: UUID(0))
        ) {
            $0.pendingPlaybackTransition = nil
        }

        #expect(
            rolledBackInstallations.value
                == [PlaybackItemInstallation(id: UUID(0))]
        )
        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrack == confirmedSongs[1])
        #expect(store.state.status == .playing)
    }

    // MARK: - Automatic Completion

    @Test
    func delayedCompletionDoesNotReplaceAPendingUserSelection() async {
        let tracks = makeTracks()
        let queue = IdentifiedArray(uniqueElements: tracks)
        let targetTrackID = tracks[2].id
        let resource = makeResource(for: targetTrackID)
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            queue: .init(
                tracks: queue,
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
            $0.playbackItem.load = { _, _ in }
            $0.playbackItem.commit = { _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                targetTrackID,
                loadedResults: queue
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: queue,
                targetTrackID: targetTrackID,
                origin: .selection
            )
        }
        await store.receive(
            .resolveTransition(
                requestID: UUID(0),
                trackID: targetTrackID
            )
        )
        await resolveProbe.waitUntilStarted()

        await store.send(.observationReceived(.completed(tracks[0].id)))
        await store.receive(.currentTrackCompleted(tracks[0].id))

        #expect(!resolveProbe.hasObservedCancellation)
        #expect(store.state.queue.currentTrackID == tracks[0].id)

        resolveProbe.succeed(with: resource)
        await store.receive(
            .transitionResourceResolved(
                requestID: UUID(0),
                resource: resource
            )
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        let snapshot = makeSnapshot(
            itemID: targetTrackID,
            status: .playing,
            position: 0,
            duration: 120
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: snapshot
        )
        await store.receive(
            .queue(.replace(queue, startingAt: targetTrackID))
        ) {
            $0.queue.currentTrackID = targetTrackID
        }
        await store.receive(.timeline(.positionObserved(0)))
        await finishPendingCommit(in: store, settlement: settlement)

        #expect(store.state.queue.currentTrackID == targetTrackID)
        #expect(!resolveProbe.hasObservedCancellation)
    }

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
                targetTrackID: tracks[targetIndex].id,
                origin: .navigation
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
        #expect(
            store.state.pendingPlaybackTransition?.origin == .navigation
        )
        #expect(
            store.state.pendingPlaybackTransition?.hasLoadedItem == false
        )
        #expect(store.state.queue.repeatMode == repeatMode)

        await cancelPlaybackTransition(in: store)
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
                targetTrackID: tracks[1].id,
                origin: .navigation
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[1].id)
        )
        await probe.waitUntilStarted()

        await cancelPlaybackTransition(in: store)
        await probe.waitUntilCancelled()
    }

    // MARK: - Confirmation Queue Policy

    @Test
    func navigationConfirmationPreservesTheTraversalOrderAndModes() async {
        let tracks = makeTracks()
        let confirmedQueue = IdentifiedArray(uniqueElements: tracks)
        let shuffledOrder = PlaybackQueueOrder(
            trackIDs: [tracks[2].id, tracks[0].id, tracks[1].id]
        )
        let resource = makeResource(for: tracks[0].id)
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: shuffledOrder,
                currentTrackID: tracks[2].id,
                repeatMode: .all,
                shuffleMode: .tracks
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in }
            $0.playbackItem.commit = { _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(.nextTapped)
        await store.receive(.queue(.nextTapped))
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[0].id)))
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: confirmedQueue,
                targetTrackID: tracks[0].id,
                origin: .navigation
            )
        }
        await store.receive(
            .resolveTransition(requestID: UUID(0), trackID: tracks[0].id)
        )
        await store.receive(
            .transitionResourceResolved(requestID: UUID(0), resource: resource)
        )
        await store.receive(
            .loadTransition(requestID: UUID(0), resource: resource)
        )
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        let snapshot = makeSnapshot(
            itemID: tracks[0].id,
            status: .playing,
            position: 0
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: snapshot
        )
        await store.receive(.queue(.currentTrackConfirmed(tracks[0].id))) {
            $0.queue.currentTrackID = tracks[0].id
        }
        await store.receive(.timeline(.positionObserved(0)))
        await finishPendingCommit(in: store, settlement: settlement)

        #expect(store.state.queue.playbackOrder == shuffledOrder)
        #expect(store.state.queue.shuffleMode == .tracks)
        #expect(store.state.queue.repeatMode == .all)
        #expect(store.state.queue.tracks == confirmedQueue)
        #expect(store.state.queue.currentTrackID == tracks[0].id)
    }

    @Test
    func repeatOneRestartsOnlyAfterTheReloadedItemIsInstalled() async {
        let tracks = makeTracks()
        let confirmedQueue = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[1].id)
        let loadProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[1].id,
                repeatMode: .one,
                shuffleMode: .off
            ),
            status: .playing,
            timeline: .init(
                confirmedPosition: 180,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            )
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in try await loadProbe.run() }
            $0.playbackItem.commit = { _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(.observationReceived(.completed(tracks[1].id)))
        await store.receive(.currentTrackCompleted(tracks[1].id))
        await store.receive(.queue(.currentTrackCompleted(tracks[1].id)))
        await store.receive(
            .queue(.delegate(.transitionRequested(tracks[1].id)))
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: confirmedQueue,
                targetTrackID: tracks[1].id,
                origin: .navigation
            )
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
        await loadProbe.waitUntilStarted()

        // The player still holds the finished item, so this identity is stale.
        let staleSnapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .paused,
            position: 180
        )
        await store.send(.observationReceived(.snapshot(staleSnapshot)))
        await store.receive(.reconcileSnapshot(staleSnapshot)) {
            $0.status = .paused
            $0.timeline.isSeekable = true
        }
        await store.receive(.queue(.currentTrackConfirmed(tracks[1].id)))
        await store.receive(.timeline(.positionObserved(180)))

        #expect(
            store.state.pendingPlaybackTransition?.targetTrackID
                == tracks[1].id
        )
        #expect(
            store.state.pendingPlaybackTransition?.hasLoadedItem == false
        )
        #expect(!loadProbe.hasObservedCancellation)

        loadProbe.succeed()
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        let restartSnapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .playing,
            position: 0
        )
        await store.send(.observationReceived(.snapshot(restartSnapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: restartSnapshot
        )
        await store.receive(.queue(.currentTrackConfirmed(tracks[1].id)))
        await store.receive(.timeline(.positionObserved(0))) {
            $0.timeline.confirmedPosition = 0
        }
        await finishPendingCommit(in: store, settlement: settlement)

        #expect(store.state.queue.repeatMode == .one)
        #expect(store.state.queue.currentTrackID == tracks[1].id)
        #expect(store.state.status == .playing)
    }

    @Test
    func selectionConfirmationReplacesTheQueueAndResetsModes() async {
        let confirmedSongs = makeTracks(prefix: "confirmed")
        let confirmedQueue = IdentifiedArray(uniqueElements: confirmedSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextResults = IdentifiedArray(uniqueElements: nextSongs)
        let resource = makeResource(for: nextSongs[1].id)
        let store = makeStore(
            queue: .init(
                tracks: confirmedQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: [
                        confirmedSongs[2].id,
                        confirmedSongs[0].id,
                        confirmedSongs[1].id,
                    ]
                ),
                currentTrackID: confirmedSongs[2].id,
                repeatMode: .all,
                shuffleMode: .tracks
            ),
            status: .playing
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in }
            $0.playbackItem.commit = { _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                nextSongs[1].id,
                loadedResults: nextResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextResults,
                targetTrackID: nextSongs[1].id,
                origin: .selection
            )
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
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        let snapshot = makeSnapshot(
            itemID: nextSongs[1].id,
            status: .playing,
            position: 0
        )
        await store.send(.observationReceived(.snapshot(snapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: snapshot
        )
        await store.receive(
            .queue(.replace(nextResults, startingAt: nextSongs[1].id))
        ) {
            $0.queue.tracks = nextResults
            $0.queue.playbackOrder = PlaybackQueueOrder(
                trackIDs: Array(nextResults.ids)
            )
            $0.queue.currentTrackID = nextSongs[1].id
            $0.queue.repeatMode = .off
            $0.queue.shuffleMode = .off
        }
        await store.receive(.timeline(.positionObserved(0)))
        await finishPendingCommit(in: store, settlement: settlement)

        #expect(store.state.queue.tracks == nextResults)
        #expect(store.state.queue.repeatMode == .off)
        #expect(store.state.queue.shuffleMode == .off)
    }

    @Test
    func reselectingTheCurrentTrackReloadsBeforeConfirming() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let resource = makeResource(for: tracks[1].id)
        let loadProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            queue: .init(
                tracks: loadedResults,
                playbackOrder: PlaybackQueueOrder(trackIDs: tracks.map(\.id)),
                currentTrackID: tracks[1].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .playing,
            timeline: .init(
                confirmedPosition: 42,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            )
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in try await loadProbe.run() }
            $0.playbackItem.commit = { _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(
            .selectionReceived(
                tracks[1].id,
                loadedResults: loadedResults
            )
        ) {
            $0.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id,
                origin: .selection
            )
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
        await loadProbe.waitUntilStarted()

        // The player is still mid-track on the item the user asked to restart.
        let staleSnapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .playing,
            position: 42
        )
        await store.send(.observationReceived(.snapshot(staleSnapshot)))
        await store.receive(.reconcileSnapshot(staleSnapshot)) {
            $0.timeline.isSeekable = true
        }
        await store.receive(.queue(.currentTrackConfirmed(tracks[1].id)))
        await store.receive(.timeline(.positionObserved(42)))

        #expect(
            store.state.pendingPlaybackTransition?.hasLoadedItem == false
        )
        #expect(!loadProbe.hasObservedCancellation)

        loadProbe.succeed()
        await store.receive(.transitionItemLoaded(requestID: UUID(0))) {
            $0.pendingPlaybackTransition?.hasLoadedItem = true
        }
        await store.receive(.playTransition(requestID: UUID(0)))
        await store.receive(.transitionPlayRequested(requestID: UUID(0)))

        let restartSnapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .playing,
            position: 0
        )
        await store.send(.observationReceived(.snapshot(restartSnapshot)))
        let settlement = await beginPendingCommit(
            in: store,
            snapshot: restartSnapshot
        )
        await store.receive(
            .queue(.replace(loadedResults, startingAt: tracks[1].id))
        )
        await store.receive(.timeline(.positionObserved(0))) {
            $0.timeline.confirmedPosition = 0
        }
        await finishPendingCommit(in: store, settlement: settlement)

        #expect(store.state.timeline.position == 0)
        #expect(store.state.queue.currentTrackID == tracks[1].id)
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

    private func cancelPlaybackTransition(
        in store: TestStoreOf<PlaybackFeature>
    ) async {
        guard let pending = store.state.pendingPlaybackTransition else {
            Issue.record("Expected a pending playback transition")
            return
        }
        let installation = pending.rollbackInstallation
        await store.send(.cancelPlaybackTransition) {
            $0.pendingPlaybackTransition?.settlement = .rollingBack(
                .abandoning(
                    installation,
                    followUp: .none
                )
            )
        }
        await store.receive(
            .transitionRollbackCompleted(requestID: pending.requestID)
        ) {
            $0.pendingPlaybackTransition = nil
        }
    }

    private func beginPendingCommit(
        in store: TestStoreOf<PlaybackFeature>,
        snapshot: PlaybackSnapshot
    ) async -> (
        requestID: UUID,
        installation: PlaybackItemInstallation
    ) {
        guard let pending = store.state.pendingPlaybackTransition else {
            Issue.record("Expected a pending playback transition")
            let requestID = UUID(255)
            return (
                requestID,
                PlaybackItemInstallation(id: requestID)
            )
        }
        let commit = PendingPlaybackTransition.Commit(snapshot: snapshot)
        await store.receive(.reconcileSnapshot(snapshot)) {
            if $0.failureNotice?.trackID == snapshot.currentTrackID {
                $0.failureNotice = nil
            }
            $0.pendingPlaybackTransition?.settlement = .committing(commit)
        }
        await store.receive(
            .transitionCommitCompleted(
                requestID: pending.requestID,
                installation: pending.installation
            )
        ) {
            let preservesStoppedStatus =
                $0.status == .stopped
                && snapshot.currentTrackID == $0.queue.currentTrackID
                && snapshot.status == .paused
            if !preservesStoppedStatus {
                $0.status = snapshot.status
            }
            $0.timeline.duration = snapshot.duration
            $0.timeline.isSeekable = snapshot.isSeekable
            $0.pendingPlaybackTransition?.settlement =
                .applyingCommit(commit)
        }
        return (pending.requestID, pending.installation)
    }

    private func finishPendingCommit(
        in store: TestStoreOf<PlaybackFeature>,
        settlement: (
            requestID: UUID,
            installation: PlaybackItemInstallation
        )
    ) async {
        await store.receive(
            .transitionConfirmationApplied(
                requestID: settlement.requestID,
                installation: settlement.installation
            )
        ) {
            $0.pendingPlaybackTransition = nil
        }
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
        timeline: PlaybackTimelineFeature.State = .init(
            confirmedPosition: 0,
            duration: nil,
            isSeekable: false,
            interaction: .idle
        ),
        pendingPlaybackTransition: PendingPlaybackTransition? = nil,
        pendingStatusChange: PlaybackFeature.PendingStatusChange? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackFeature> {
        TestStore(
            initialState: PlaybackFeature.State(
                queue: queue,
                status: status,
                failureNotice: failureNotice,
                timeline: timeline,
                pendingPlaybackTransition: pendingPlaybackTransition,
                pendingStatusChange: pendingStatusChange,
                isPlayerPresented: false
            )
        ) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackItem.rollback = { _ in }
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
        duration: TimeInterval? = nil,
        isSeekable: Bool = true
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            currentTrackID: itemID,
            status: status,
            position: position,
            duration: duration,
            isSeekable: isSeekable
        )
    }
}
