import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppVideoRouteTests {
    @Test
    func openingVideoCreatesEmptyRoute() async {
        let store = TestStore(initialState: makeState()) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.pause = {}
        }

        await store.send(.openVideoButtonTapped) {
            $0.playbackTransition = .openingVideo
        }
        await store.receive(\.openVideoSucceeded) {
            $0.playbackTransition = nil
            $0.video = makeVideoState()
        }
    }

    @Test
    func closingVideoCancelsChildWorkPausesClearsThenDismisses() async throws {
        let videoURL = try VideoTestFixtures.url("video.mp4")
        let events = LockIsolated<[String]>([])
        let (observationStarted, observationStartedContinuation) =
            AsyncStream<Void>.makeStream()
        let (snapshots, snapshotsContinuation) =
            AsyncStream<VideoPlaybackSnapshot>.makeStream()
        let (loadStarted, loadStartedContinuation) = AsyncStream<Void>.makeStream()
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let store = TestStore(
            initialState: makeState(
                video: makeVideoState(urlText: videoURL.absoluteString)
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.videoPlayback.playbackSnapshots = {
                observationStartedContinuation.yield()
                return snapshots
            }
            $0.videoPlayback.load = { _ in
                loadStartedContinuation.yield()
                try await Task.sleep(for: .seconds(60))
            }
            $0.videoPlayback.pause = {
                events.withValue { $0.append("pause") }
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            }
            $0.videoPlayback.clear = {
                events.withValue { $0.append("clear") }
            }
        }

        await store.send(.video(.task)) {
            $0.video?.observationID = UUID(0)
        }
        var observationStartedIterator = observationStarted.makeAsyncIterator()
        _ = await observationStartedIterator.next()

        await store.send(.video(.loadSubmitted)) {
            $0.video?.phase = .loading(
                requestID: UUID(1),
                lastSnapshot: .idle
            )
        }
        var loadStartedIterator = loadStarted.makeAsyncIterator()
        _ = await loadStartedIterator.next()

        await store.send(.video(.closeButtonTapped))
        await store.receive(.video(.delegate(.closeRequested)))
        await store.receive(.closeVideoRequested) {
            $0.videoCloseRequestID = UUID(2)
        }
        await store.receive(.video(.routeExited)) {
            $0.video?.phase = .observing(.idle)
            $0.video?.observationID = nil
        }

        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()
        #expect(events.value == ["pause"])

        let lateSnapshot = VideoPlaybackSnapshot(
            status: .playing,
            currentTime: 12
        )
        await store.send(
            .video(
                .loadSucceeded(
                    requestID: UUID(1),
                    url: videoURL
                )
            )
        )
        await store.send(
            .video(
                .snapshotReceived(
                    observationID: UUID(0),
                    snapshot: lateSnapshot
                )
            )
        )

        resumePauseContinuation.yield()
        resumePauseContinuation.finish()
        await store.receive(.closeVideoFinished(UUID(2))) {
            $0.video = nil
            $0.videoCloseRequestID = nil
        }

        #expect(events.value == ["pause", "clear"])
        await store.finish()
        observationStartedContinuation.finish()
        snapshotsContinuation.finish()
        loadStartedContinuation.finish()
        pauseStartedContinuation.finish()
    }

    @Test
    func duplicateCloseAndOpenWhileClosingAreIgnored() async {
        let events = LockIsolated<[String]>([])
        let (pauseStarted, pauseStartedContinuation) = AsyncStream<Void>.makeStream()
        let (resumePause, resumePauseContinuation) = AsyncStream<Void>.makeStream()
        let video = makeVideoState(urlText: "original")
        let store = TestStore(initialState: makeState(video: video)) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.videoPlayback.pause = {
                events.withValue { $0.append("pause") }
                pauseStartedContinuation.yield()
                for await _ in resumePause { break }
            }
            $0.videoPlayback.clear = {
                events.withValue { $0.append("clear") }
            }
        }

        await store.send(.openVideoButtonTapped)
        await store.send(.closeVideoRequested) {
            $0.videoCloseRequestID = UUID(0)
        }
        await store.receive(.video(.routeExited))

        var pauseStartedIterator = pauseStarted.makeAsyncIterator()
        _ = await pauseStartedIterator.next()

        await store.send(.closeVideoRequested)
        await store.send(.openVideoButtonTapped)
        #expect(store.state.video == video)
        #expect(events.value == ["pause"])

        resumePauseContinuation.yield()
        resumePauseContinuation.finish()
        await store.receive(.closeVideoFinished(UUID(0))) {
            $0.video = nil
            $0.videoCloseRequestID = nil
        }

        #expect(events.value == ["pause", "clear"])
        pauseStartedContinuation.finish()
    }

    @Test
    func staleCloseCompletionIsIgnored() async {
        let video = makeVideoState(urlText: "active")
        let store = TestStore(
            initialState: makeState(
                video: video,
                videoCloseRequestID: UUID(1)
            )
        ) {
            AppFeature()
        }

        await store.send(.closeVideoFinished(UUID(0)))
        #expect(store.state.video == video)
        #expect(store.state.videoCloseRequestID == UUID(1))

        await store.send(.closeVideoFinished(UUID(1))) {
            $0.video = nil
            $0.videoCloseRequestID = nil
        }
    }

    // MARK: - Helpers

    private func makeState(
        video: VideoPlaybackFeature.State? = nil,
        videoCloseRequestID: UUID? = nil
    ) -> AppFeature.State {
        AppFeature.State(
            registeredProviders: [.appleMusic],
            activeProviderID: "apple-music",
            search: SearchFeature.State(
                query: "",
                phase: .idle,
                playbackEligibility: .unknown
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: .allEnabled
            ),
            isPlayerPresented: false,
            video: video,
            videoCloseRequestID: videoCloseRequestID,
            playbackTransition: nil
        )
    }

    private func makeVideoState(
        urlText: String = ""
    ) -> VideoPlaybackFeature.State {
        VideoPlaybackFeature.State(
            urlText: urlText,
            loadedVideoURL: nil,
            phase: .observing(.idle),
            observationID: nil
        )
    }
}
