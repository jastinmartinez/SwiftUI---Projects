import AVFoundation
import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AVPlayerControllerTests {
    @Test
    func preparedItemReplacesInjectedPlayerWithoutAutoplay() throws {
        let player = AVPlayer()
        let item = AVPlayerItem(
            url: try VideoTestFixtures.url("video.mp4")
        )
        let controller = AVPlayerController(player: player)

        controller.replaceCurrentItem(with: item)

        #expect(player.currentItem === item)
        #expect(player.rate == 0)
    }

    @Test
    func clearRemovesCurrentItem() throws {
        let player = AVPlayer(
            playerItem: AVPlayerItem(
                url: try VideoTestFixtures.url("video.mp4")
            )
        )
        let controller = AVPlayerController(player: player)

        controller.clear()

        #expect(player.currentItem == nil)
    }

    @Test
    func playbackObservationStartsWithCurrentSnapshot() async throws {
        let controller = AVPlayerController(player: AVPlayer())
        let receivedSnapshot = LockIsolated<VideoPlaybackSnapshot?>(nil)
        let observationTask = Task { @MainActor in
            var iterator = controller.playbackSnapshots().makeAsyncIterator()
            let snapshot = await iterator.next()
            receivedSnapshot.setValue(snapshot)
        }

        try await Task.sleep(for: .milliseconds(100))
        observationTask.cancel()

        #expect(receivedSnapshot.value == .idle)
    }

    @Test
    func completedValuesProduceEndedStatus() {
        let status = VideoPlaybackStatus(
            hasCurrentItem: true,
            timeControlStatus: .paused,
            currentTime: 10,
            duration: 10
        )

        #expect(status == .ended)
    }
}
