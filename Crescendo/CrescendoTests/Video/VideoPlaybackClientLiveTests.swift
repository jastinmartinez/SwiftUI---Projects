import AVFoundation
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct VideoPlaybackClientLiveTests {
    @Test
    func loadCoordinatesItemPreparationAndReplacement() async throws {
        let url = makeURL("video.mp4")
        let item = AVPlayerItem(url: url)
        let player = AVPlayer()
        let controller = VideoPlaybackController(player: player)
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
    func preparationFailurePreservesCurrentItem() async {
        let oldItem = AVPlayerItem(url: makeURL("old.mp4"))
        let player = AVPlayer(playerItem: oldItem)
        let controller = VideoPlaybackController(player: player)
        let itemLoader = VideoPlayableItemLoader(
            load: { _ in throw VideoPlaybackError.notPlayable }
        )
        let videoPlayback = VideoPlaybackClient.live(
            controller: controller,
            itemLoader: itemLoader
        )

        await #expect(throws: VideoPlaybackError.notPlayable) {
            try await videoPlayback.load(makeURL("new.mp4"))
        }

        #expect(player.currentItem === oldItem)
    }

    @Test
    func cancellationDuringPreparationPreservesCurrentItem() async {
        let oldItem = AVPlayerItem(url: makeURL("old.mp4"))
        let newItem = AVPlayerItem(url: makeURL("new.mp4"))
        let player = AVPlayer(playerItem: oldItem)
        let controller = VideoPlaybackController(player: player)
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
            try await videoPlayback.load(makeURL("new.mp4"))
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

    // MARK: - Helpers

    private func makeURL(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }
}
