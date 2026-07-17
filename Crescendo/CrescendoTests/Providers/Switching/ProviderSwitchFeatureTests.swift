import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct ProviderSwitchFeatureTests {
    @Test
    func startPausesWithFreshRequestIdentity() async {
        let pauseCount = LockIsolated(0)
        let store = makeStore(pause: { pauseCount.withValue { $0 += 1 } })

        await store.send(.start) {
            $0.phase = .pausing(targetProviderID: "future", requestID: UUID(0))
        }
        await store.receive(.pauseSucceeded(requestID: UUID(0)))
        await store.receive(.delegate(.readyToConnect("future")))

        #expect(pauseCount.value == 1)
    }

    @Test
    func pauseFailureDelegatesFailure() async {
        let store = makeStore(pause: { throw MusicProviderError.playbackFailed })

        await store.send(.start) {
            $0.phase = .pausing(targetProviderID: "future", requestID: UUID(0))
        }
        await store.receive(.pauseFailed(requestID: UUID(0)))
        await store.receive(.delegate(.failed))
    }

    @Test
    func changingTargetReplacesPauseRequest() async {
        let pauseCount = LockIsolated(0)
        let (firstPauseStarted, firstPauseStartedContinuation) =
            AsyncStream<Void>.makeStream()
        let store = makeStore(pause: {
            let count = pauseCount.withValue {
                $0 += 1
                return $0
            }
            if count == 1 {
                firstPauseStartedContinuation.yield()
                try await Task.sleep(for: .seconds(60))
            }
        })

        await store.send(.start) {
            $0.phase = .pausing(targetProviderID: "future", requestID: UUID(0))
        }
        var firstPauseStartedIterator = firstPauseStarted.makeAsyncIterator()
        _ = await firstPauseStartedIterator.next()

        await store.send(.targetChanged("third")) {
            $0.phase = .pausing(targetProviderID: "third", requestID: UUID(1))
        }
        await store.receive(.pauseSucceeded(requestID: UUID(1)))
        await store.receive(.delegate(.readyToConnect("third")))

        #expect(pauseCount.value == 2)
        firstPauseStartedContinuation.finish()
    }

    @Test
    func selectingSamePendingTargetIsNoOp() async {
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let store = makeStore(pause: {
            pauseStartedContinuation.yield()
            try await Task.sleep(for: .seconds(60))
        })

        await store.send(.start) {
            $0.phase = .pausing(targetProviderID: "future", requestID: UUID(0))
        }
        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()

        await store.send(.targetChanged("future"))
        #expect(
            store.state.phase
                == .pausing(targetProviderID: "future", requestID: UUID(0))
        )

        await store.send(.cancel)
        await store.receive(.delegate(.cancelled))
        pauseStartedContinuation.finish()
    }

    @Test
    func cancelCancelsPauseAndDelegatesCancellation() async {
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let store = makeStore(pause: {
            pauseStartedContinuation.yield()
            try await Task.sleep(for: .seconds(60))
        })

        await store.send(.start) {
            $0.phase = .pausing(targetProviderID: "future", requestID: UUID(0))
        }
        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()

        await store.send(.cancel)
        await store.receive(.delegate(.cancelled))
        await store.finish()
        pauseStartedContinuation.finish()
    }

    @Test
    func stalePauseResponsesCannotCompleteNewerTransaction() async {
        let state = ProviderSwitchFeature.State(
            sourceProviderID: .appleMusic,
            phase: .pausing(targetProviderID: "third", requestID: UUID(1))
        )
        let store = makeStore(state: state)

        await store.send(.pauseSucceeded(requestID: UUID(0)))
        await store.send(.pauseFailed(requestID: UUID(0)))

        #expect(store.state == state)
    }

    // MARK: - Helpers

    private func makeStore(
        state: ProviderSwitchFeature.State = ProviderSwitchFeature.State(
            sourceProviderID: .appleMusic,
            phase: .ready(targetProviderID: "future")
        ),
        pause: @escaping @Sendable () async throws -> Void = {}
    ) -> TestStoreOf<ProviderSwitchFeature> {
        TestStore(initialState: state) {
            ProviderSwitchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.pause = pause
        }
    }
}
