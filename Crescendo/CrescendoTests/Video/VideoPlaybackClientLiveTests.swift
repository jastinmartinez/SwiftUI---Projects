import AVFoundation
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct VideoPlaybackClientLiveTests {
    @Test
    func loadCoordinatesItemPreparationAndReplacement() async throws {
        let url = try VideoTestFixtures.url("video.mp4")
        let item = AVPlayerItem(url: url)
        let player = AVPlayer()
        let controller = AVPlayerController(player: player)
        var preparedURLs: [URL] = []
        let itemLoader = VideoPlayableItemLoader(
            load: { submittedURL in
                preparedURLs.append(submittedURL)
                return item
            }
        )
        let videoPlayback = VideoPlaybackClient.live(
            controller: controller,
            itemLoader: itemLoader
        )

        try await videoPlayback.load(url)

        #expect(preparedURLs == [url])
        #expect(player.currentItem === item)
    }

    @Test
    func preparationFailurePreservesCurrentItem() async throws {
        let oldItem = AVPlayerItem(
            url: try VideoTestFixtures.url("old.mp4")
        )
        let newURL = try VideoTestFixtures.url("new.mp4")
        let player = AVPlayer(playerItem: oldItem)
        let controller = AVPlayerController(player: player)
        let itemLoader = VideoPlayableItemLoader(
            load: { _ in throw VideoPlaybackError.notPlayable }
        )
        let videoPlayback = VideoPlaybackClient.live(
            controller: controller,
            itemLoader: itemLoader
        )

        await #expect(throws: VideoPlaybackError.notPlayable) {
            try await videoPlayback.load(newURL)
        }

        #expect(player.currentItem === oldItem)
    }

    @Test
    func cancellationDuringPreparationPreservesCurrentItem() async throws {
        let oldItem = AVPlayerItem(
            url: try VideoTestFixtures.url("old.mp4")
        )
        let newURL = try VideoTestFixtures.url("new.mp4")
        let newItem = AVPlayerItem(url: newURL)
        let player = AVPlayer(playerItem: oldItem)
        let controller = AVPlayerController(player: player)
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (resume, resumeContinuation) = AsyncStream<Void>.makeStream()
        let itemLoader = VideoPlayableItemLoader(
            load: { _ in
                startedContinuation.yield()
                for await _ in resume { break }
                return newItem
            }
        )
        let videoPlayback = VideoPlaybackClient.live(
            controller: controller,
            itemLoader: itemLoader
        )
        let loadTask = Task {
            try await videoPlayback.load(newURL)
        }
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()

        loadTask.cancel()
        resumeContinuation.yield()
        resumeContinuation.finish()

        await #expect(throws: CancellationError.self) {
            try await loadTask.value
        }
        #expect(player.currentItem === oldItem)
        startedContinuation.finish()
    }
}
