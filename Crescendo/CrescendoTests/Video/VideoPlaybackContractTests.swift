import Foundation
import Testing

@testable import Crescendo

struct VideoPlaybackContractTests {
    @Test
    func statePreservesTheProvidedPlaybackPhase() {
        let state = VideoPlaybackFeature.State(
            urlText: "",
            loadedVideoURL: nil,
            phase: .observing(.idle),
            observationID: nil
        )

        #expect(state.urlText.isEmpty)
        #expect(state.loadedVideoURL == nil)
        #expect(state.phase == .observing(.idle))
        #expect(state.observationID == nil)
    }

    @Test
    func phaseRetainsTheLatestValidSnapshot() {
        let snapshot = VideoPlaybackSnapshot(
            status: .paused,
            currentTime: 42
        )
        let requestID = UUID(1)
        let loading = VideoPlaybackFeature.Phase.loading(
            requestID: requestID,
            lastSnapshot: snapshot
        )
        let failed = VideoPlaybackFeature.Phase.failed(
            .notPlayable,
            lastSnapshot: snapshot
        )

        #expect(loading.snapshot == snapshot)
        #expect(failed.snapshot == snapshot)
    }

    @Test
    func fakeClientPublishesNormalizedSnapshot() async {
        let expectedSnapshot = VideoPlaybackSnapshot(
            status: .ready,
            currentTime: 0
        )
        let videoPlayback = VideoPlaybackClient(
            load: { _ in },
            pause: {},
            clear: {},
            seek: { _ in },
            playbackSnapshots: {
                AsyncStream { continuation in
                    continuation.yield(expectedSnapshot)
                    continuation.finish()
                }
            }
        )
        var snapshots = await videoPlayback.playbackSnapshots().makeAsyncIterator()

        let receivedSnapshot = await snapshots.next()

        #expect(receivedSnapshot == expectedSnapshot)
    }
}
