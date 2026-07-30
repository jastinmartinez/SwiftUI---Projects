import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AppFeatureTests {
    @Test
    func appTaskStartsPlaybackObservationOnly() async {
        let store = TestStore(initialState: makeState()) {
            AppFeature()
        } withDependencies: {
            $0.playbackObservation = PlaybackObservationClient(
                observations: { AsyncStream { $0.finish() } }
            )
        }

        await store.send(.task)
        await store.receive(.playback(.task))
    }

    private func makeState() -> AppFeature.State {
        AppFeature.State(
            search: SearchFeature.State(
                query: "",
                status: .idle,
                providerID: .testProvider
            ),
            playback: PlaybackFeature.State(
                queue: PlaybackQueueFeature.State(
                    current: nil
                ),
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: 0,
                    duration: nil,
                    isSeekable: false,
                    interaction: .idle
                ),
                session: PlaybackSessionFeature.State(
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
