import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackTransitionFeatureTests {
    @Test
    func transitionRoutesTheTargetWithoutQueueContext() async {
        let jamendo = makeTrack(providerID: .jamendo, nativeID: "remote")
        let local = makeTrack(providerID: .localMusic, nativeID: "local")
        let intent = PlaybackTransitionFeature.Intent(
            targetTrackID: local.id,
            baselineTrackID: jamendo.id
        )
        let resolvedIDs = LockIsolated<[TrackID]>([])
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let jamendoResource = makeResource(for: jamendo.id)
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [
                    .jamendo: PlaybackResourceClient { _ in
                        Issue.record("The non-target provider must not resolve")
                        return jamendoResource
                    },
                    .localMusic: PlaybackResourceClient { trackID in
                        resolvedIDs.withValue { $0.append(trackID) }
                        return try await resolveProbe.run()
                    },
                ]
            )
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await resolveProbe.waitUntilStarted()

        #expect(resolvedIDs.value == [local.id])

        resolveProbe.fail(with: CancellationError())
        await store.finish()
    }

    @Test
    func confirmedPlaybackSurvivesWhileTheNextTrackResolves() async {
        let tracks = makeTracks()
        let baselineID = tracks[0].id
        let intent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: baselineID
        )
        let baselineSnapshot = makeSnapshot(
            itemID: baselineID,
            status: .playing,
            position: 42
        )
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await resolveProbe.run()
            }
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await resolveProbe.waitUntilStarted()

        await store.send(.snapshotReceived(baselineSnapshot))
        await store.receive(
            .delegate(.confirmedSnapshotReady(baselineSnapshot))
        )

        resolveProbe.fail(with: CancellationError())
        await store.finish()
    }

    @Test
    func confirmedPlaybackSurvivesWhileTheNextTrackLoads() async {
        let tracks = makeTracks()
        let baselineID = tracks[0].id
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID,
            baselineTrackID: baselineID
        )
        let resource = makeResource(for: targetID)
        let baselineSnapshot = makeSnapshot(
            itemID: baselineID,
            status: .playing,
            position: 42
        )
        let loadProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in
                try await loadProbe.run()
            }
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolved(requestID: UUID(0), resource: resource)
        ) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await loadProbe.waitUntilStarted()

        await store.send(.snapshotReceived(baselineSnapshot))
        await store.receive(
            .delegate(.confirmedSnapshotReady(baselineSnapshot))
        )

        loadProbe.fail(with: CancellationError())
        await store.finish()
    }

    @Test
    func resolutionReceivesOnlyTheTargetTrackIdentity() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let resource = makeResource(for: targetID)
        let resolvedTrackIDs = LockIsolated<[TrackID]>([])
        let loadProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { trackID in
                resolvedTrackIDs.withValue { $0.append(trackID) }
                return resource
            }
            $0.playbackItem.load = { _, _ in
                try await loadProbe.run()
            }
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolved(requestID: UUID(0), resource: resource)
        ) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await loadProbe.waitUntilStarted()

        #expect(resolvedTrackIDs.value == [targetID])

        loadProbe.fail(with: CancellationError())
        await store.finish()
    }

    @Test
    func itemLoadingReceivesTheResolvedResourceWithoutADuplicateIdentity()
        async
    {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let resource = makeResource(for: targetID)
        let loadedResources = LockIsolated<[PlaybackResource]>([])
        let installations = LockIsolated<[PlaybackItemInstallation]>([])
        let playProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { loaded, installation in
                loadedResources.withValue { $0.append(loaded) }
                installations.withValue { $0.append(installation) }
            }
            $0.playbackTransport.play = playProbe.run
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolved(requestID: UUID(0), resource: resource)
        ) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.receive(.itemLoaded(requestID: UUID(0))) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: nil
                )
            )
        }
        await playProbe.waitUntilStarted()

        #expect(loadedResources.value == [resource])
        #expect(installations.value == [.init(id: UUID(0))])

        playProbe.fail(with: CancellationError())
        await store.finish()
    }

    @Test
    func playIsRequestedOnlyAfterItemLoadingSucceeds() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let resource = makeResource(for: targetID)
        let calls = LockIsolated<[String]>([])
        let loadProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                calls.withValue { $0.append("resolve") }
                return resource
            }
            $0.playbackItem.load = { _, _ in
                calls.withValue { $0.append("load") }
                try await loadProbe.run()
            }
            $0.playbackTransport.play = {
                calls.withValue { $0.append("play") }
            }
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolved(requestID: UUID(0), resource: resource)
        ) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await loadProbe.waitUntilStarted()
        #expect(calls.value == ["resolve", "load"])

        loadProbe.succeed()
        await store.receive(.itemLoaded(requestID: UUID(0))) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: nil
                )
            )
        }
        await store.receive(.playbackRequested(requestID: UUID(0))) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: nil
                )
            )
        }

        #expect(calls.value == ["resolve", "load", "play"])
    }

    @Test
    func noWorkflowStageConfirmsTheTargetTrack() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let resource = makeResource(for: targetID)
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in }
            $0.playbackTransport.play = {}
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolved(requestID: UUID(0), resource: resource)
        ) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.receive(.itemLoaded(requestID: UUID(0))) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: nil
                )
            )
        }
        await store.receive(.playbackRequested(requestID: UUID(0))) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: nil
                )
            )
        }

        #expect(
            store.state.phase
                == .preparing(
                    transaction(intent: intent),
                    .init(
                        stage: .awaitingConfirmation,
                        latestTargetSnapshot: nil
                    )
                )
        )
    }

    @Test
    func failedResolutionClearsOnlyTheMatchingTransition() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await resolveProbe.run()
            }
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await resolveProbe.waitUntilStarted()

        await store.send(
            .resourceResolutionFailed(
                requestID: UUID(99),
                failure: .resourceUnavailable
            )
        )

        resolveProbe.fail(with: PlaybackFailure.unsupportedResource)
        await store.receive(
            .resourceResolutionFailed(
                requestID: UUID(0),
                failure: .unsupportedResource
            )
        )
        await store.receive(
            .delegate(
                .completed(
                    .failed(
                        trackID: targetID,
                        failure: .unsupportedResource
                    )
                )
            )
        )
    }

    @Test
    func failedItemLoadClearsTheTransitionAndNeverRequestsPlay() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let resource = makeResource(for: targetID)
        let playCount = LockIsolated(0)
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in
                throw MusicProviderError.network
            }
            $0.playbackTransport.play = {
                playCount.withValue { $0 += 1 }
            }
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolved(requestID: UUID(0), resource: resource)
        ) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .itemLoadFailed(
                requestID: UUID(0),
                failure: .preparationFailed
            )
        ) {
            let transaction = self.transaction(intent: intent)
            $0.phase = .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .failure(
                        trackID: targetID,
                        failure: .preparationFailed
                    ),
                    followUp: nil
                )
            )
        }
        await store.receive(.rollbackRequested(requestID: UUID(0)))
        await store.receive(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(
            .delegate(
                .completed(
                    .failed(
                        trackID: targetID,
                        failure: .preparationFailed
                    )
                )
            )
        )

        #expect(playCount.value == 0)
    }

    @Test
    func preAcknowledgementTargetObservationCannotConfirmBeforeInterruption()
        async
    {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let snapshot = makeSnapshot(
            itemID: targetID,
            status: .waiting,
            position: 2
        )
        let store = makeStore(
            phase: .preparing(
                transaction(intent: intent),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        )

        await store.send(.snapshotReceived(snapshot)) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .loading,
                    latestTargetSnapshot: snapshot
                )
            )
        }

        #expect(
            store.state.phase
                == .preparing(
                    transaction(intent: intent),
                    .init(
                        stage: .loading,
                        latestTargetSnapshot: snapshot
                    )
                )
        )
    }

    @Test
    func latestPreAcknowledgementSnapshotReplaysAfterPlayStarts() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let firstSnapshot = makeSnapshot(
            itemID: targetID,
            status: .waiting,
            position: 2
        )
        let latestSnapshot = makeSnapshot(
            itemID: targetID,
            status: .playing,
            position: 9
        )
        let store = makeStore(
            phase: .preparing(
                transaction(intent: intent),
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: firstSnapshot
                )
            )
        ) {
            $0.playbackItem.commit = { _ in }
        }

        await store.send(.snapshotReceived(latestSnapshot)) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: latestSnapshot
                )
            )
        }
        await store.send(.playbackRequested(requestID: UUID(0))) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: latestSnapshot
                )
            )
        }
        await store.receive(
            .cachedSnapshotReplayRequested(
                requestID: UUID(0),
                snapshot: latestSnapshot
            )
        ) {
            $0.phase = .committing(
                self.transaction(intent: intent),
                .init(snapshot: latestSnapshot, followUp: nil)
            )
        }
        await store.receive(.commitCompleted(requestID: UUID(0))) {
            $0.phase = .applyingConfirmation(
                self.transaction(intent: intent),
                .init(snapshot: latestSnapshot, followUp: nil)
            )
        }
        await store.receive(
            .delegate(
                .confirmationReady(
                    .init(intent: intent, snapshot: latestSnapshot)
                )
            )
        )
    }

    @Test
    func liveStoreWaitsForPlayReturnBeforeReplayingLatestTargetSnapshot()
        async
    {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let resource = makeResource(for: targetID)
        let olderSnapshot = makeSnapshot(
            itemID: targetID,
            status: .waiting,
            position: 2
        )
        let newerSnapshot = makeSnapshot(
            itemID: targetID,
            status: .waiting,
            position: 9
        )
        let playProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                resource
            }
            $0.playbackItem.load = { _, _ in }
            $0.playbackItem.commit = { _ in }
            $0.playbackTransport.play = playProbe.run
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolved(requestID: UUID(0), resource: resource)
        ) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.receive(.itemLoaded(requestID: UUID(0))) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: nil
                )
            )
        }
        await playProbe.waitUntilStarted()

        await store.send(.snapshotReceived(olderSnapshot)) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: olderSnapshot
                )
            )
        }
        await store.send(.snapshotReceived(newerSnapshot)) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: newerSnapshot
                )
            )
        }

        playProbe.succeed()
        await store.receive(.playbackRequested(requestID: UUID(0))) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: newerSnapshot
                )
            )
        }
        await store.receive(
            .cachedSnapshotReplayRequested(
                requestID: UUID(0),
                snapshot: newerSnapshot
            )
        ) {
            $0.phase = .committing(
                self.transaction(intent: intent),
                .init(snapshot: newerSnapshot, followUp: nil)
            )
        }
        await store.receive(.commitCompleted(requestID: UUID(0))) {
            $0.phase = .applyingConfirmation(
                self.transaction(intent: intent),
                .init(snapshot: newerSnapshot, followUp: nil)
            )
        }
        await store.receive(
            .delegate(
                .confirmationReady(
                    .init(intent: intent, snapshot: newerSnapshot)
                )
            )
        )
    }

    @Test
    func newerLiveSnapshotWinsBeforeCachedReplayArrives() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let cachedSnapshot = makeSnapshot(
            itemID: targetID,
            status: .waiting,
            position: 2
        )
        let newerSnapshot = makeSnapshot(
            itemID: targetID,
            status: .playing,
            position: 9
        )
        let commitProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            phase: .preparing(
                transaction(intent: intent),
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: cachedSnapshot
                )
            )
        ) {
            $0.playbackItem.commit = { _ in
                _ = try? await commitProbe.run()
            }
        }

        await store.send(.snapshotReceived(newerSnapshot)) {
            $0.phase = .committing(
                self.transaction(intent: intent),
                .init(snapshot: newerSnapshot, followUp: nil)
            )
        }
        await commitProbe.waitUntilStarted()
        await store.send(
            .cachedSnapshotReplayRequested(
                requestID: UUID(0),
                snapshot: cachedSnapshot
            )
        )

        #expect(
            store.state.phase
                == .committing(
                    transaction(intent: intent),
                    .init(snapshot: newerSnapshot, followUp: nil)
                )
        )

        commitProbe.succeed()
        await store.receive(.commitCompleted(requestID: UUID(0))) {
            $0.phase = .applyingConfirmation(
                self.transaction(intent: intent),
                .init(snapshot: newerSnapshot, followUp: nil)
            )
        }
        await store.receive(
            .delegate(
                .confirmationReady(
                    .init(intent: intent, snapshot: newerSnapshot)
                )
            )
        )
    }

    @Test
    func matchingSnapshotCommitsBeforeDelegatingConfirmation() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let transaction = transaction(intent: intent)
        let snapshot = makeSnapshot(
            itemID: targetID,
            status: .playing,
            position: 9
        )
        let committedInstallations =
            LockIsolated<[PlaybackItemInstallation]>([])
        let store = makeStore(
            phase: .preparing(
                transaction,
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: snapshot
                )
            )
        ) {
            $0.playbackItem.commit = { installation in
                committedInstallations.withValue {
                    $0.append(installation)
                }
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.snapshotReceived(snapshot)) {
            $0.phase = .committing(
                transaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        }
        await store.finish()

        #expect(committedInstallations.value == [.init(id: UUID(0))])
    }

    @Test
    func matchingCommitCompletionStartsConfirmationApplication() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id
        )
        let transaction = transaction(intent: intent)
        let snapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .playing,
            position: 9
        )
        let store = makeStore(
            phase: .committing(
                transaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        )

        await store.send(.commitCompleted(requestID: UUID(99)))
        await store.send(.commitCompleted(requestID: UUID(0))) {
            $0.phase = .applyingConfirmation(
                transaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        }
        await store.receive(
            .delegate(
                .confirmationReady(
                    .init(intent: intent, snapshot: snapshot)
                )
            )
        )
        await store.send(.confirmationApplied)
        await store.receive(.delegate(.completed(.confirmed)))
    }

    @Test
    func confirmationPreservesOnlyPlaybackIdentities() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let snapshot = makeSnapshot(
            itemID: tracks[1].id,
            status: .playing,
            position: 9
        )
        let store = makeStore(
            phase: .committing(
                transaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        )

        await store.send(.commitCompleted(requestID: UUID(0))) {
            $0.phase = .applyingConfirmation(
                transaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        }
        await store.receive(
            .delegate(
                .confirmationReady(
                    .init(intent: intent, snapshot: snapshot)
                )
            )
        )
    }

    @Test
    func newestMatchingSnapshotWinsWhileCommitIsSuspended() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let transaction = transaction(intent: intent)
        let firstSnapshot = makeSnapshot(
            itemID: targetID,
            status: .waiting,
            position: 2
        )
        let latestSnapshot = makeSnapshot(
            itemID: targetID,
            status: .playing,
            position: 9
        )
        let store = makeStore(
            phase: .committing(
                transaction,
                .init(snapshot: firstSnapshot, followUp: nil)
            )
        )

        await store.send(.snapshotReceived(latestSnapshot)) {
            $0.phase = .committing(
                transaction,
                .init(snapshot: latestSnapshot, followUp: nil)
            )
        }

    }

    @Test
    func newestMatchingSnapshotWinsWhileConfirmationApplicationIsPending()
        async
    {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let transaction = transaction(intent: intent)
        let firstSnapshot = makeSnapshot(
            itemID: targetID,
            status: .waiting,
            position: 2
        )
        let latestSnapshot = makeSnapshot(
            itemID: targetID,
            status: .playing,
            position: 9
        )
        let store = makeStore(
            phase: .applyingConfirmation(
                transaction,
                .init(snapshot: firstSnapshot, followUp: nil)
            )
        )

        await store.send(.snapshotReceived(latestSnapshot)) {
            $0.phase = .applyingConfirmation(
                transaction,
                .init(snapshot: latestSnapshot, followUp: nil)
            )
        }
    }

    @Test
    func cancellationAfterLoadingBeginsRollsBackBeforeCompleting() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let rollbacks = LockIsolated<[PlaybackItemInstallation]>([])
        let store = makeStore(
            phase: .preparing(
                transaction,
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        ) {
            $0.playbackItem.rollback = { installation in
                rollbacks.withValue { $0.append(installation) }
            }
        }

        await store.send(.cancel) {
            $0.phase = .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .cancellation,
                    followUp: nil
                )
            )
        }
        await store.receive(.rollbackRequested(requestID: UUID(0)))
        await store.receive(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(.delegate(.completed(.cancelled)))

        #expect(rollbacks.value == [transaction.installation])
    }

    @Test
    func failedPlayRequestRollsBackBeforeReportingFailure() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let store = makeStore(
            phase: .preparing(
                transaction,
                .init(
                    stage: .requestingPlayback,
                    latestTargetSnapshot: nil
                )
            )
        )

        await store.send(
            .playbackRequestFailed(
                requestID: UUID(0),
                failure: .playbackFailed
            )
        ) {
            $0.phase = .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .failure(
                        trackID: targetID,
                        failure: .playbackFailed
                    ),
                    followUp: nil
                )
            )
        }
        await store.receive(.rollbackRequested(requestID: UUID(0)))
        await store.receive(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(
            .delegate(
                .completed(
                    .failed(
                        trackID: targetID,
                        failure: .playbackFailed
                    )
                )
            )
        )
    }

    @Test
    func supersedingAnInstalledTargetRollsBackBeforeStartingLatestIntent()
        async
    {
        let tracks = makeTracks()
        let oldIntent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: tracks[0].id
        )
        let latestIntent = makeIntent(
            targetTrackID: tracks[2].id,
            baselineTrackID: tracks[0].id
        )
        let oldTransaction = transaction(
            intent: oldIntent,
            requestID: UUID(99)
        )
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            phase: .preparing(
                oldTransaction,
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await resolveProbe.run()
            }
        }

        await store.send(.supersede(latestIntent)) {
            $0.phase = .rollingBack(
                oldTransaction,
                .init(
                    installation: oldTransaction.installation,
                    reason: .supersession,
                    followUp: .transition(latestIntent)
                )
            )
        }
        await store.receive(
            .rollbackRequested(requestID: oldTransaction.requestID)
        )
        await store.receive(
            .rollbackCompleted(requestID: oldTransaction.requestID)
        ) {
            $0.phase = .starting(latestIntent)
        }
        await store.receive(.start) {
            $0.phase = .preparing(
                self.transaction(intent: latestIntent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await resolveProbe.waitUntilStarted()

        await store.send(.itemLoaded(requestID: oldTransaction.requestID))

        resolveProbe.fail(with: CancellationError())
        await store.finish()
    }

    @Test
    func latestFollowUpReplacesEarlierIntentWhileConfirmationIsPending()
        async
    {
        let tracks = makeTracks(prefix: "old")
        let oldIntent = makeIntent(
            targetTrackID: tracks[1].id
        )
        let oldTransaction = transaction(
            intent: oldIntent,
            requestID: UUID(99)
        )
        let snapshot = makeSnapshot(
            itemID: oldIntent.targetTrackID,
            status: .playing,
            position: 4
        )
        let firstTracks = makeTracks(prefix: "first")
        let firstIntent = makeIntent(
            targetTrackID: firstTracks[1].id,
            baselineTrackID: oldIntent.targetTrackID
        )
        let latestTracks = makeTracks(prefix: "latest")
        let latestIntent = makeIntent(
            targetTrackID: latestTracks[1].id,
            baselineTrackID: oldIntent.targetTrackID
        )
        let resolveProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            phase: .applyingConfirmation(
                oldTransaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await resolveProbe.run()
            }
        }

        await store.send(.supersede(firstIntent)) {
            $0.phase = .applyingConfirmation(
                oldTransaction,
                .init(
                    snapshot: snapshot,
                    followUp: .transition(firstIntent)
                )
            )
        }
        await store.send(.supersede(latestIntent)) {
            $0.phase = .applyingConfirmation(
                oldTransaction,
                .init(
                    snapshot: snapshot,
                    followUp: .transition(latestIntent)
                )
            )
        }
        await store.send(.confirmationApplied) {
            $0.phase = .starting(latestIntent)
        }
        await store.receive(.start) {
            $0.phase = .preparing(
                self.transaction(intent: latestIntent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await resolveProbe.waitUntilStarted()

        resolveProbe.fail(with: CancellationError())
        await store.finish()
    }

    @Test
    func stopRestoresInstalledTargetBeforeBecomingReady() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let stopCount = LockIsolated(0)
        let store = makeStore(
            phase: .preparing(
                transaction,
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        ) {
            $0.playbackTransport.stop = {
                stopCount.withValue { $0 += 1 }
                return .completed
            }
        }

        await store.send(.stopRequested) {
            $0.phase = .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .cancellation,
                    followUp: .stop
                )
            )
        }
        await store.receive(.rollbackRequested(requestID: UUID(0)))
        await store.receive(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(.delegate(.completed(.stopReady)))

        #expect(stopCount.value == 0)
    }

    @Test
    func stopWaitsForCommitAndReplacesQueuedTransition() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id
        )
        let transaction = transaction(intent: intent)
        let snapshot = makeSnapshot(
            itemID: intent.targetTrackID,
            status: .playing,
            position: 4
        )
        let queuedTracks = makeTracks(prefix: "queued")
        let queuedIntent = makeIntent(
            targetTrackID: queuedTracks[1].id,
            baselineTrackID: intent.targetTrackID
        )
        let stopCount = LockIsolated(0)
        let store = makeStore(
            phase: .committing(
                transaction,
                .init(
                    snapshot: snapshot,
                    followUp: .transition(queuedIntent)
                )
            )
        ) {
            $0.playbackTransport.stop = {
                stopCount.withValue { $0 += 1 }
                return .completed
            }
        }

        await store.send(.stopRequested) {
            $0.phase = .committing(
                transaction,
                .init(snapshot: snapshot, followUp: .stop)
            )
        }
        await store.send(.commitCompleted(requestID: UUID(0))) {
            $0.phase = .applyingConfirmation(
                transaction,
                .init(snapshot: snapshot, followUp: .stop)
            )
        }
        await store.receive(
            .delegate(
                .confirmationReady(
                    .init(intent: intent, snapshot: snapshot)
                )
            )
        )
        await store.send(.confirmationApplied)
        await store.receive(.delegate(.completed(.stopReady)))

        #expect(stopCount.value == 0)
    }

    @Test
    func runtimeFailureForPendingTargetStartsRollback() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let store = makeStore(
            phase: .preparing(
                transaction,
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: makeSnapshot(
                        itemID: targetID,
                        status: .waiting,
                        position: 2
                    )
                )
            )
        )

        await store.send(
            .runtimeFailureReceived(targetID, .playbackFailed)
        ) {
            $0.phase = .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .failure(
                        trackID: targetID,
                        failure: .playbackFailed
                    ),
                    followUp: nil
                )
            )
        }
        await store.receive(.rollbackRequested(requestID: UUID(0)))
        await store.receive(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(
            .delegate(
                .completed(
                    .failed(
                        trackID: targetID,
                        failure: .playbackFailed
                    )
                )
            )
        )
    }

    @Test
    func runtimeFailureRoutesBaselineAndIgnoresUnrelatedIdentity() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let store = makeStore(
            phase: .preparing(
                transaction,
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        )

        await store.send(
            .runtimeFailureReceived(tracks[2].id, .playbackFailed)
        )
        await store.send(
            .runtimeFailureReceived(tracks[0].id, .playbackFailed)
        )
        await store.receive(
            .delegate(
                .confirmedPlaybackFailed(
                    trackID: tracks[0].id,
                    failure: .playbackFailed
                )
            )
        )
    }

    @Test
    func runtimeFailureAfterCommitKeepsPermanentTargetSettlement() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let snapshot = makeSnapshot(
            itemID: targetID,
            status: .playing,
            position: 7
        )
        let phase: PlaybackTransitionFeature.Phase =
            .applyingConfirmation(
                transaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        let store = makeStore(phase: phase)

        await store.send(
            .runtimeFailureReceived(targetID, .playbackFailed)
        )
        await store.receive(
            .delegate(
                .confirmedPlaybackFailed(
                    trackID: targetID,
                    failure: .playbackFailed
                )
            )
        )
        #expect(store.state.phase == phase)

        await store.send(.confirmationApplied)
        await store.receive(.delegate(.completed(.confirmed)))
    }

    @Test
    func runtimeFailureDuringCommitRollsBackAndIgnoresStaleCompletion()
        async
    {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let snapshot = makeSnapshot(
            itemID: targetID,
            status: .playing,
            position: 7
        )
        let rollbackProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(
            phase: .committing(
                transaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        ) {
            $0.playbackItem.rollback = { _ in
                _ = try? await rollbackProbe.run()
            }
        }

        await store.send(
            .runtimeFailureReceived(targetID, .playbackFailed)
        ) {
            $0.phase = .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .failure(
                        trackID: targetID,
                        failure: .playbackFailed
                    ),
                    followUp: nil
                )
            )
        }
        await store.receive(.rollbackRequested(requestID: UUID(0)))
        await rollbackProbe.waitUntilStarted()

        await store.send(.commitCompleted(requestID: UUID(0)))

        rollbackProbe.succeed()
        await store.receive(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(
            .delegate(
                .completed(
                    .failed(
                        trackID: targetID,
                        failure: .playbackFailed
                    )
                )
            )
        )
    }

    @Test
    func delayedPlayFailureAfterCommitSurfacesWithoutRollback() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID
        )
        let transaction = transaction(intent: intent)
        let snapshot = makeSnapshot(
            itemID: targetID,
            status: .playing,
            position: 7
        )
        let phase: PlaybackTransitionFeature.Phase = .committing(
            transaction,
            .init(snapshot: snapshot, followUp: nil)
        )
        let rollbackCount = LockIsolated(0)
        let store = makeStore(phase: phase) {
            $0.playbackItem.rollback = { _ in
                rollbackCount.withValue { $0 += 1 }
            }
        }

        await store.send(
            .playbackRequestFailed(
                requestID: UUID(0),
                failure: .playbackFailed
            )
        )
        await store.receive(
            .delegate(
                .confirmedPlaybackFailed(
                    trackID: targetID,
                    failure: .playbackFailed
                )
            )
        )

        #expect(store.state.phase == phase)
        #expect(rollbackCount.value == 0)
    }

    @Test
    func rollbackPreservesStopAndAcceptsOnlyBaselineEvidence() async {
        let tracks = makeTracks()
        let baselineID = tracks[0].id
        let targetID = tracks[1].id
        let intent = makeIntent(
            targetTrackID: targetID,
            baselineTrackID: baselineID
        )
        let transaction = transaction(intent: intent)
        let rollback = PlaybackTransitionFeature.Rollback(
            installation: transaction.installation,
            reason: .cancellation,
            followUp: .stop
        )
        let baselineSnapshot = makeSnapshot(
            itemID: baselineID,
            status: .playing,
            position: 12
        )
        let targetSnapshot = makeSnapshot(
            itemID: targetID,
            status: .waiting,
            position: 1
        )
        let store = makeStore(
            phase: .rollingBack(transaction, rollback)
        )

        await store.send(.snapshotReceived(targetSnapshot))
        await store.send(
            .runtimeFailureReceived(targetID, .playbackFailed)
        )
        #expect(
            store.state.phase == .rollingBack(transaction, rollback)
        )

        await store.send(.snapshotReceived(baselineSnapshot))
        await store.receive(
            .delegate(.confirmedSnapshotReady(baselineSnapshot))
        )
        await store.send(
            .runtimeFailureReceived(baselineID, .playbackFailed)
        )
        await store.receive(
            .delegate(
                .confirmedPlaybackFailed(
                    trackID: baselineID,
                    failure: .playbackFailed
                )
            )
        )
        #expect(
            store.state.phase == .rollingBack(transaction, rollback)
        )

        await store.send(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(.delegate(.completed(.stopReady)))
    }

    @Test
    func resolvingSupersessionStartsLatestAndIgnoresOldResponse() async {
        let oldTracks = makeTracks(prefix: "old")
        let oldIntent = makeIntent(
            targetTrackID: oldTracks[1].id
        )
        let oldTransaction = transaction(
            intent: oldIntent,
            requestID: UUID(99)
        )
        let latestTracks = makeTracks(prefix: "latest")
        let latestIntent = makeIntent(
            targetTrackID: latestTracks[1].id
        )
        let latestProbe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            phase: .preparing(
                oldTransaction,
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await latestProbe.run()
            }
        }

        await store.send(.supersede(latestIntent)) {
            $0.phase = .starting(latestIntent)
        }
        await store.receive(.start) {
            $0.phase = .preparing(
                self.transaction(intent: latestIntent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await latestProbe.waitUntilStarted()

        await store.send(
            .resourceResolved(
                requestID: oldTransaction.requestID,
                resource: makeResource(
                    for: oldIntent.targetTrackID
                )
            )
        )

        latestProbe.fail(with: CancellationError())
        await store.finish()
    }

    @Test
    func stopDuringResolutionNeedsNoRollbackOrTransportStop() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id
        )
        let transaction = transaction(intent: intent)
        let rollbackCount = LockIsolated(0)
        let stopCount = LockIsolated(0)
        let store = makeStore(
            phase: .preparing(
                transaction,
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        ) {
            $0.playbackItem.rollback = { _ in
                rollbackCount.withValue { $0 += 1 }
            }
            $0.playbackTransport.stop = {
                stopCount.withValue { $0 += 1 }
                return .completed
            }
        }

        await store.send(.stopRequested)
        await store.receive(.delegate(.completed(.stopReady)))

        #expect(rollbackCount.value == 0)
        #expect(stopCount.value == 0)
    }

    @Test
    func cancellationDuringSettlementClearsQueuedFollowUp() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id
        )
        let transaction = transaction(intent: intent)
        let snapshot = makeSnapshot(
            itemID: intent.targetTrackID,
            status: .playing,
            position: 8
        )
        let nextTracks = makeTracks(prefix: "next")
        let nextIntent = makeIntent(
            targetTrackID: nextTracks[1].id,
            baselineTrackID: intent.targetTrackID
        )
        let store = makeStore(
            phase: .applyingConfirmation(
                transaction,
                .init(
                    snapshot: snapshot,
                    followUp: .transition(nextIntent)
                )
            )
        )

        await store.send(.cancel) {
            $0.phase = .applyingConfirmation(
                transaction,
                .init(snapshot: snapshot, followUp: nil)
            )
        }
        await store.send(.confirmationApplied)
        await store.receive(.delegate(.completed(.confirmed)))
    }

    @Test
    func rollbackReconcilesNilSnapshotForNilBaseline() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: nil
        )
        let transaction = transaction(intent: intent)
        let nilSnapshot = makeSnapshot(
            itemID: nil,
            status: .idle,
            position: 0
        )
        let store = makeStore(
            phase: .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .cancellation,
                    followUp: nil
                )
            )
        )

        await store.send(.snapshotReceived(nilSnapshot))
        await store.receive(
            .delegate(.confirmedSnapshotReady(nilSnapshot))
        )
    }

    @Test
    func settlementIgnoresBaselineUnrelatedAndIdentitylessSnapshots()
        async
    {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: tracks[0].id
        )
        let transaction = transaction(intent: intent)
        let targetSnapshot = makeSnapshot(
            itemID: intent.targetTrackID,
            status: .playing,
            position: 8
        )
        let phase: PlaybackTransitionFeature.Phase =
            .applyingConfirmation(
                transaction,
                .init(snapshot: targetSnapshot, followUp: nil)
            )
        let store = makeStore(phase: phase)

        await store.send(
            .snapshotReceived(
                makeSnapshot(
                    itemID: tracks[0].id,
                    status: .playing,
                    position: 3
                )
            )
        )
        await store.send(
            .snapshotReceived(
                makeSnapshot(
                    itemID: tracks[2].id,
                    status: .playing,
                    position: 3
                )
            )
        )
        await store.send(
            .snapshotReceived(
                makeSnapshot(
                    itemID: nil,
                    status: .idle,
                    position: 0
                )
            )
        )

        #expect(store.state.phase == phase)
    }

    @Test
    func staleSettlementResponsesCannotChangeNewerTransaction() async {
        let tracks = makeTracks(prefix: "new")
        let intent = makeIntent(
            targetTrackID: tracks[1].id
        )
        let transaction = transaction(
            intent: intent,
            requestID: UUID(1)
        )
        let phase: PlaybackTransitionFeature.Phase = .preparing(
            transaction,
            .init(stage: .loading, latestTargetSnapshot: nil)
        )
        let store = makeStore(phase: phase)

        await store.send(.commitCompleted(requestID: UUID(0)))
        await store.send(.rollbackCompleted(requestID: UUID(0)))

        #expect(store.state.phase == phase)
    }

    @Test
    func staleRollbackRequestCannotTouchCurrentTransaction() async {
        let tracks = makeTracks()
        let intent = makeIntent(targetTrackID: tracks[1].id)
        let transaction = transaction(
            intent: intent,
            requestID: UUID(1)
        )
        let rollbackCount = LockIsolated(0)
        let store = makeStore(
            phase: .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .cancellation,
                    followUp: nil
                )
            )
        ) {
            $0.playbackItem.rollback = { _ in
                rollbackCount.withValue { $0 += 1 }
            }
        }

        await store.send(.rollbackRequested(requestID: UUID(0)))

        #expect(rollbackCount.value == 0)
    }

    @Test
    func missingTargetProviderFailsWithoutTouchingConfirmedPlayback()
        async
    {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id,
            baselineTrackID: tracks[0].id
        )
        let store = makeStore(intent: intent) {
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [:]
            )
        }

        await store.send(.start) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(stage: .resolving, latestTargetSnapshot: nil)
            )
        }
        await store.receive(
            .resourceResolutionFailed(
                requestID: UUID(0),
                failure: .resourceUnavailable
            )
        )
        await store.receive(
            .delegate(
                .completed(
                    .failed(
                        trackID: intent.targetTrackID,
                        failure: .resourceUnavailable
                    )
                )
            )
        )
    }

    @Test
    func stopReplacesLatestFollowUpDuringRollback() async {
        let tracks = makeTracks()
        let intent = makeIntent(
            targetTrackID: tracks[1].id
        )
        let transaction = transaction(intent: intent)
        let queuedTracks = makeTracks(prefix: "queued")
        let queuedIntent = makeIntent(
            targetTrackID: queuedTracks[1].id
        )
        let store = makeStore(
            phase: .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .supersession,
                    followUp: .transition(queuedIntent)
                )
            )
        )

        await store.send(.stopRequested) {
            $0.phase = .rollingBack(
                transaction,
                .init(
                    installation: transaction.installation,
                    reason: .supersession,
                    followUp: .stop
                )
            )
        }
        await store.send(.rollbackCompleted(requestID: UUID(0)))
        await store.receive(.delegate(.completed(.stopReady)))
    }

    private func makeStore(
        intent: PlaybackTransitionFeature.Intent,
        configureDependencies:
            (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackTransitionFeature> {
        makeStore(
            phase: .starting(intent),
            configureDependencies: configureDependencies
        )
    }

    private func makeStore(
        phase: PlaybackTransitionFeature.Phase,
        configureDependencies:
            (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackTransitionFeature> {
        TestStore(
            initialState: PlaybackTransitionFeature.State(phase: phase)
        ) {
            PlaybackTransitionFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackItem.rollback = { _ in }
            configureDependencies(&$0)
        }
    }

    private func transaction(
        intent: PlaybackTransitionFeature.Intent,
        requestID: UUID = UUID(0)
    ) -> PlaybackTransitionFeature.Transaction {
        PlaybackTransitionFeature.Transaction(
            requestID: requestID,
            intent: intent
        )
    }

    private func makeIntent(
        targetTrackID: TrackID,
        baselineTrackID: TrackID? = nil
    ) -> PlaybackTransitionFeature.Intent {
        PlaybackTransitionFeature.Intent(
            targetTrackID: targetTrackID,
            baselineTrackID: baselineTrackID
        )
    }

    private func makeResourceClients(
        resolve:
            @escaping @Sendable (TrackID) async throws -> PlaybackResource
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
        position: TimeInterval
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            currentTrackID: itemID,
            status: status,
            position: position,
            duration: 180,
            isSeekable: true
        )
    }

    private var providerID: ProviderID {
        "fake"
    }
}
