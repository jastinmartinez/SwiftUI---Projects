import AVFoundation
import AVKit
import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AVPlayerSessionTests {
    @Test
    func preparedItemReplacesInjectedPlayerWithoutAutoplay() throws {
        let player = AVPlayer()
        let item = AVPlayerItem(
            url: try VideoTestFixtures.url("video.mp4")
        )
        let session = AVPlayerSession(player: player)

        session.replaceCurrentItem(with: item)

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
        let session = AVPlayerSession(player: player)

        session.clear()

        #expect(player.currentItem == nil)
    }

    @Test
    func playbackObservationStartsWithCurrentSnapshot() async throws {
        let session = AVPlayerSession(player: AVPlayer())
        let receivedSnapshot = LockIsolated<VideoPlaybackSnapshot?>(nil)
        let observationTask = Task { @MainActor in
            var iterator = session.playbackSnapshots().makeAsyncIterator()
            let snapshot = await iterator.next()
            receivedSnapshot.setValue(snapshot)
        }

        try await Task.sleep(for: .milliseconds(100))
        observationTask.cancel()

        #expect(receivedSnapshot.value == .idle)
    }

    @Test
    func attachingViewControllerUsesOwnedPlayer() {
        let player = AVPlayer()
        let session = AVPlayerSession(player: player)
        let playerViewController = AVPlayerViewController()

        session.attach(to: playerViewController)

        #expect(playerViewController.player === player)
    }

    @Test
    func liveFactoryCreatesIndependentSessions() {
        #expect(AVPlayerSession.live() !== AVPlayerSession.live())
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
