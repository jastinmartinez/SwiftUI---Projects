import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AppReducerTests {
    @Test
    func appTaskStartsPlaybackObservationOnly() async {
        let store = TestStore(initialState: makeState()) {
            AppReducer()
        } withDependencies: {
            $0.playbackObservation = PlaybackObservationClient(
                observations: { AsyncStream { $0.finish() } }
            )
        }

        await store.send(.task)
        await store.receive(.playback(.task))
    }

    private func makeState() -> AppReducer.State {
        AppReducer.State(
            search: SearchReducer.State(
                query: "",
                status: .idle,
                providerID: .testProvider
            ),
            playback: PlaybackReducer.State(
                queue: PlaybackQueueReducer.State(
                    current: nil
                ),
                timeline: PlaybackTimelineReducer.State(
                    confirmedPosition: 0,
                    duration: nil,
                    isSeekable: false,
                    interaction: .idle
                ),
                session: PlaybackSessionReducer.State(
                    status: .idle,
                    pendingStatusChange: nil
                ),
                transition: nil,
                failureNotice: nil,
                isPlayerPresented: false
            )
        )
    }
}
