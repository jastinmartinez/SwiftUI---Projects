import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct MusicPlaybackTimelineFeatureTests {
    @Test
    func positionChangesReplaceDraftWithoutSeeking() async {
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let store = makeStore(seekPositions: seekPositions)

        await store.send(.positionChanged(10)) {
            $0.interaction = .dragging(position: 10)
        }
        await store.send(.positionChanged(20)) {
            $0.interaction = .dragging(position: 20)
        }

        #expect(seekPositions.value.isEmpty)
    }

    @Test
    func dragEndSeeksLatestPositionExactlyOnce() async {
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let store = makeStore(
            interaction: .dragging(position: 20),
            seekPositions: seekPositions
        )

        await store.send(.dragEnded) {
            $0.interaction = .seeking(
                requestID: UUID(0),
                position: 20
            )
        }
        await store.receive(.seekSucceeded(requestID: UUID(0))) {
            $0.interaction = .idle
        }

        #expect(seekPositions.value == [20])
    }

    @Test
    func seekSuccessClearsOnlyMatchingRequest() async {
        let activeRequestID = UUID(1)
        let store = makeStore(
            interaction: .seeking(
                requestID: activeRequestID,
                position: 20
            )
        )

        await store.send(.seekSucceeded(requestID: UUID(0)))
        await store.send(.seekSucceeded(requestID: activeRequestID)) {
            $0.interaction = .idle
        }
    }

    @Test
    func newDragCancelsSeekAndStaleCompletionCannotClearDraft() async {
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let (finishSeek, finishSeekContinuation) = AsyncStream<Void>.makeStream()
        let store = makeStore(
            interaction: .dragging(position: 10),
            seekPositions: seekPositions,
            finishSeek: finishSeek
        )

        await store.send(.dragEnded) {
            $0.interaction = .seeking(
                requestID: UUID(0),
                position: 10
            )
        }
        await store.send(.positionChanged(20)) {
            $0.interaction = .dragging(position: 20)
        }
        await store.send(.seekSucceeded(requestID: UUID(0)))

        #expect(seekPositions.value == [10])
        #expect(store.state.interaction == .dragging(position: 20))
        finishSeekContinuation.finish()
    }

    @Test
    func seekFailureClearsMatchingRequestAndDelegatesError() async {
        let store = makeStore(
            interaction: .dragging(position: 20),
            seekError: .network
        )

        await store.send(.dragEnded) {
            $0.interaction = .seeking(
                requestID: UUID(0),
                position: 20
            )
        }
        await store.receive(
            .seekFailed(requestID: UUID(0), error: .network)
        ) {
            $0.interaction = .idle
        }
        await store.receive(.delegate(.transportFailed(.network)))
    }

    @Test
    func dragEndFromIdleDoesNothing() async {
        let seekPositions = LockIsolated<[TimeInterval]>([])
        let store = makeStore(seekPositions: seekPositions)

        await store.send(.dragEnded)

        #expect(seekPositions.value.isEmpty)
    }

    @Test
    func resetCancelsLiveSeekAndDropsLateFailure() async {
        let suspendedSeek = SuspendedSeekProbe()
        let store = makeStore(
            interaction: .dragging(position: 20),
            seekOperation: suspendedSeek.callAsFunction
        )

        await store.send(.dragEnded) {
            $0.interaction = .seeking(
                requestID: UUID(0),
                position: 20
            )
        }
        await suspendedSeek.waitUntilStarted()

        await store.send(.reset) {
            $0.interaction = .idle
        }
        #expect(suspendedSeek.cancellationObserved.value)

        suspendedSeek.fail(with: .network)
        await store.finish()
        #expect(store.state.interaction == .idle)
    }

    // MARK: - Helpers

    private func makeStore(
        interaction: MusicPlaybackTimelineFeature.Interaction = .idle,
        seekPositions: LockIsolated<[TimeInterval]> = LockIsolated([]),
        seekError: MusicProviderError? = nil,
        finishSeek: AsyncStream<Void>? = nil,
        seekOperation: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) -> TestStoreOf<MusicPlaybackTimelineFeature> {
        TestStore(
            initialState: MusicPlaybackTimelineFeature.State(
                interaction: interaction
            )
        ) {
            MusicPlaybackTimelineFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackControl.seek = { position in
                seekPositions.withValue { $0.append(position) }
                if let seekOperation {
                    try await seekOperation(position)
                    return
                }
                if let seekError {
                    throw seekError
                }
                if let finishSeek {
                    for await _ in finishSeek { break }
                }
            }
        }
    }
}

// MARK: - Suspended Effect Probe

struct SuspendedSeekProbe: Sendable {
    let cancellationObserved = LockIsolated(false)

    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let pendingContinuation =
        LockIsolated<CheckedContinuation<Void, any Error>?>(nil)

    init() {
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
    }

    func callAsFunction(_ position: TimeInterval) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingContinuation.withValue { $0 = continuation }
                startedContinuation.yield()
            }
        } onCancel: {
            cancellationObserved.withValue { $0 = true }
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

    func fail(with error: MusicProviderError) {
        pendingContinuation.withValue { pendingContinuation in
            let continuation = pendingContinuation
            pendingContinuation = nil
            continuation?.resume(throwing: error)
        }
    }
}
