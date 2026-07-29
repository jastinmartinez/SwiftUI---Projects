import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackTransitionFeatureTests {
    @Test
    func selectionRoutesTheTargetThroughItsOwnProvider() async {
        let jamendo = makeTrack(providerID: .jamendo, nativeID: "remote")
        let local = makeTrack(providerID: .localMusic, nativeID: "local")
        let queue: IdentifiedArrayOf<Track> = [jamendo, local]
        let intent = makeIntent(queue: queue, targetTrackID: local.id)
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
        )
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
            queue: IdentifiedArray(uniqueElements: tracks),
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
        )

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
        )
    }

    @Test
    func liveStoreWaitsForPlayReturnBeforeReplayingLatestTargetSnapshot()
        async
    {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            queue: IdentifiedArray(uniqueElements: tracks),
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
        )
    }

    @Test
    func newerLiveSnapshotWinsBeforeCachedReplayArrives() async {
        let tracks = makeTracks()
        let targetID = tracks[1].id
        let intent = makeIntent(
            queue: IdentifiedArray(uniqueElements: tracks),
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
        let store = makeStore(
            phase: .preparing(
                transaction(intent: intent),
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: cachedSnapshot
                )
            )
        )

        await store.send(.snapshotReceived(newerSnapshot)) {
            $0.phase = .preparing(
                self.transaction(intent: intent),
                .init(
                    stage: .awaitingConfirmation,
                    latestTargetSnapshot: newerSnapshot
                )
            )
        }
        await store.send(
            .cachedSnapshotReplayRequested(
                requestID: UUID(0),
                snapshot: cachedSnapshot
            )
        )

        #expect(
            store.state.phase
                == .preparing(
                    transaction(intent: intent),
                    .init(
                        stage: .awaitingConfirmation,
                        latestTargetSnapshot: newerSnapshot
                    )
                )
        )
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
        intent: PlaybackTransitionFeature.Intent
    ) -> PlaybackTransitionFeature.Transaction {
        PlaybackTransitionFeature.Transaction(
            requestID: UUID(0),
            intent: intent
        )
    }

    private func makeIntent(
        queue: IdentifiedArrayOf<Track>,
        targetTrackID: TrackID,
        baselineTrackID: TrackID? = nil,
        origin: PlaybackTransitionFeature.Origin = .selection
    ) -> PlaybackTransitionFeature.Intent {
        PlaybackTransitionFeature.Intent(
            queue: queue,
            targetTrackID: targetTrackID,
            baselineTrackID: baselineTrackID,
            origin: origin
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
