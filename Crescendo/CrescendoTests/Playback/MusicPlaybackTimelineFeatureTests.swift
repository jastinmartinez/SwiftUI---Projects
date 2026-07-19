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

    // MARK: - Helpers

    private func makeStore(
        interaction: MusicPlaybackTimelineFeature.Interaction = .idle,
        seekPositions: LockIsolated<[TimeInterval]> = LockIsolated([]),
        seekError: MusicProviderError? = nil,
        finishSeek: AsyncStream<Void>? = nil
    ) -> TestStoreOf<MusicPlaybackTimelineFeature> {
        TestStore(
            initialState: MusicPlaybackTimelineFeature.State(
                interaction: interaction
            )
        ) {
            MusicPlaybackTimelineFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.musicProvider.seek = { position in
                seekPositions.withValue { $0.append(position) }
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
