import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackSessionFeatureTests {
    @Test
    func playingToggleRequestsPauseAndWaitsForConfirmation() async {
        let pauseCount = LockIsolated(0)
        let store = makeStore(status: .playing) {
            $0.playbackTransport.pause = {
                pauseCount.withValue { $0 += 1 }
            }
        }

        await store.send(.playPauseRequested) {
            $0.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .paused
            )
        }
        await store.receive(.statusCommandSucceeded(requestID: UUID(0)))

        #expect(store.state.status == .playing)
        #expect(store.state.pendingStatusChange?.target == .paused)
        #expect(pauseCount.value == 1)

        await store.send(
            .confirmedSnapshot(status: .paused, position: 12)
        ) {
            $0.status = .paused
            $0.pendingStatusChange = nil
        }
        await store.receive(.delegate(.statusConfirmed))
    }

    @Test
    func pausedToggleRequestsPlayAndWaitsForConfirmation() async {
        let playCount = LockIsolated(0)
        let store = makeStore(status: .paused) {
            $0.playbackTransport.play = {
                playCount.withValue { $0 += 1 }
            }
        }

        await store.send(.playPauseRequested) {
            $0.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .playing
            )
        }
        await store.receive(.statusCommandSucceeded(requestID: UUID(0)))

        #expect(store.state.status == .paused)
        #expect(store.state.pendingStatusChange?.target == .playing)
        #expect(playCount.value == 1)

        await store.send(
            .confirmedSnapshot(status: .playing, position: 12)
        ) {
            $0.status = .playing
            $0.pendingStatusChange = nil
        }
        await store.receive(.delegate(.statusConfirmed))
    }

    @Test
    func stoppedToggleRequestsPlayAndWaitsForConfirmation() async {
        let playCount = LockIsolated(0)
        let store = makeStore(status: .stopped) {
            $0.playbackTransport.play = {
                playCount.withValue { $0 += 1 }
            }
        }

        await store.send(.playPauseRequested) {
            $0.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .playing
            )
        }
        await store.receive(.statusCommandSucceeded(requestID: UUID(0)))

        #expect(store.state.status == .stopped)
        #expect(store.state.pendingStatusChange?.target == .playing)
        #expect(playCount.value == 1)

        await store.send(
            .confirmedSnapshot(status: .playing, position: 0)
        ) {
            $0.status = .playing
            $0.pendingStatusChange = nil
        }
        await store.receive(.delegate(.statusConfirmed))
    }

    @Test
    func nonmatchingSnapshotPreservesPendingTarget() async {
        let pending = PlaybackSessionFeature.PendingStatusChange(
            requestID: UUID(1),
            target: .playing
        )
        let store = makeStore(
            status: .paused,
            pendingStatusChange: pending
        )

        await store.send(
            .confirmedSnapshot(status: .waiting, position: 12)
        ) {
            $0.status = .waiting
        }

        #expect(store.state.pendingStatusChange == pending)
    }

    @Test
    func matchingPlayFailureClearsOnlyMatchingOperation() async {
        let store = makeStore(status: .paused) {
            $0.playbackTransport.play = {
                throw PlaybackFailure.resourceUnavailable
            }
        }

        await store.send(.playPauseRequested) {
            $0.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .playing
            )
        }
        await store.receive(
            .statusCommandFailed(
                requestID: UUID(0),
                failure: .resourceUnavailable
            )
        ) {
            $0.pendingStatusChange = nil
        }
        await store.receive(
            .delegate(.transportFailed(.resourceUnavailable))
        )

        #expect(store.state.status == .paused)
    }

    @Test
    func matchingPauseFailureClearsOnlyMatchingOperation() async {
        let store = makeStore(status: .playing) {
            $0.playbackTransport.pause = {
                throw MusicProviderError.network
            }
        }

        await store.send(.playPauseRequested) {
            $0.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .paused
            )
        }
        await store.receive(
            .statusCommandFailed(
                requestID: UUID(0),
                failure: .playbackFailed
            )
        ) {
            $0.pendingStatusChange = nil
        }
        await store.receive(
            .delegate(.transportFailed(.playbackFailed))
        )

        #expect(store.state.status == .playing)
    }

    @Test
    func staleResponseCannotClearNewerOperation() async {
        let pending = PlaybackSessionFeature.PendingStatusChange(
            requestID: UUID(1),
            target: .paused
        )
        let store = makeStore(
            status: .playing,
            pendingStatusChange: pending
        )

        await store.send(.statusCommandSucceeded(requestID: UUID(0)))
        await store.send(
            .statusCommandFailed(
                requestID: UUID(0),
                failure: .playbackFailed
            )
        )

        #expect(store.state.status == .playing)
        #expect(store.state.pendingStatusChange == pending)
    }

    @Test
    func successfulStopConfirmsStoppedWithoutTimelineDependency() async {
        let stopCount = LockIsolated(0)
        let store = makeStore(status: .playing) {
            $0.playbackTransport.stop = {
                stopCount.withValue { $0 += 1 }
                return .completed
            }
        }

        await store.send(.stopRequested) {
            $0.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .stopped
            )
        }
        await store.receive(.statusCommandSucceeded(requestID: UUID(0))) {
            $0.status = .stopped
            $0.pendingStatusChange = nil
        }
        await store.receive(.delegate(.stopCompleted))

        #expect(stopCount.value == 1)
    }

    @Test
    func failedStopPreservesConfirmedStatus() async {
        let stopCount = LockIsolated(0)
        let store = makeStore(status: .playing) {
            $0.playbackTransport.stop = {
                stopCount.withValue { $0 += 1 }
                return .interrupted
            }
        }

        await store.send(.stopRequested) {
            $0.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .stopped
            )
        }
        await store.receive(
            .statusCommandFailed(
                requestID: UUID(0),
                failure: .playbackFailed
            )
        ) {
            $0.pendingStatusChange = nil
        }
        await store.receive(
            .delegate(.transportFailed(.playbackFailed))
        )

        #expect(store.state.status == .playing)
        #expect(stopCount.value == 1)
    }

    @Test
    func cancelPendingStatusChangeClearsAndCancelsTheOperation() async {
        let pauseProbe = SuspendedOperationProbe<Void>()
        let store = makeStore(status: .playing) {
            $0.playbackTransport.pause = pauseProbe.run
        }

        await store.send(.playPauseRequested) {
            $0.pendingStatusChange = .init(
                requestID: UUID(0),
                target: .paused
            )
        }
        await pauseProbe.waitUntilStarted()

        await store.send(.cancelPendingStatusChange) {
            $0.pendingStatusChange = nil
        }
        await pauseProbe.waitUntilCancelled()

        #expect(pauseProbe.hasObservedCancellation)
        #expect(store.state.status == .playing)
    }

    @Test
    func pausedAtZeroSnapshotPreservesConfirmedStop() async {
        let store = makeStore(status: .stopped)

        await store.send(
            .confirmedSnapshot(status: .paused, position: 0)
        )

        #expect(store.state.status == .stopped)
    }

    @Test
    func playingSnapshotExitsConfirmedStop() async {
        let store = makeStore(status: .stopped)

        await store.send(
            .confirmedSnapshot(status: .playing, position: 3)
        ) {
            $0.status = .playing
        }
    }

    @Test
    func pausedSnapshotWithMotionExitsConfirmedStop() async {
        let store = makeStore(status: .stopped)

        await store.send(
            .confirmedSnapshot(status: .paused, position: 3)
        ) {
            $0.status = .paused
        }
    }

    private func makeStore(
        status: PlaybackStatus,
        pendingStatusChange:
            PlaybackSessionFeature.PendingStatusChange? = nil,
        configureDependencies:
            (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<PlaybackSessionFeature> {
        TestStore(
            initialState: PlaybackSessionFeature.State(
                status: status,
                pendingStatusChange: pendingStatusChange
            )
        ) {
            PlaybackSessionFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            configureDependencies(&$0)
        }
    }
}
