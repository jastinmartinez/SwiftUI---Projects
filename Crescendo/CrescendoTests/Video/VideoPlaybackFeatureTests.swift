import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct VideoPlaybackFeatureTests {
    @Test
    func unsupportedSchemeNeverCallsClient() async {
        let loadCalls = LockIsolated(0)
        let store = makeStore(urlText: "file:///tmp/movie.mp4") {
            $0.videoPlayback.load = { _ in
                loadCalls.withValue { $0 += 1 }
            }
        }

        await store.send(.loadSubmitted) {
            $0.phase = .failed(
                .unsupportedScheme,
                lastSnapshot: .idle
            )
        }

        #expect(loadCalls.value == 0)
    }

    @Test
    func credentialedURLNeverCallsClient() async {
        let loadCalls = LockIsolated(0)
        let store = makeStore(
            urlText: "https://user:password@example.com/video.mp4"
        ) {
            $0.videoPlayback.load = { _ in
                loadCalls.withValue { $0 += 1 }
            }
        }

        await store.send(.loadSubmitted) {
            $0.phase = .failed(
                .invalidURL,
                lastSnapshot: .idle
            )
        }

        #expect(loadCalls.value == 0)
    }

    @Test
    func successfulLoadTrimsURLAndPreservesPlaybackSnapshot() async throws {
        let url = try VideoTestFixtures.url("video.mp4")
        let snapshot = VideoPlaybackSnapshot(
            status: .paused,
            currentTime: 42
        )
        let loadedURLs = LockIsolated<[URL]>([])
        let store = makeStore(
            urlText: "  \(url.absoluteString)  ",
            phase: .observing(snapshot)
        ) {
            $0.uuid = .incrementing
            $0.videoPlayback.load = { submittedURL in
                loadedURLs.withValue { $0.append(submittedURL) }
            }
        }

        await store.send(.loadSubmitted) {
            $0.phase = .loading(
                requestID: UUID(0),
                lastSnapshot: snapshot
            )
        }
        await store.receive(
            .loadSucceeded(requestID: UUID(0), url: url)
        ) {
            $0.loadedVideoURL = url
            $0.phase = .observing(snapshot)
        }

        #expect(loadedURLs.value == [url])
    }

    @Test
    func failedLoadPreservesCurrentSourceAndPlaybackSnapshot() async throws {
        let oldURL = try VideoTestFixtures.url("old.m3u8")
        let snapshot = VideoPlaybackSnapshot(
            status: .playing,
            currentTime: 12
        )
        let store = makeStore(
            urlText: try VideoTestFixtures.url("new.mp4").absoluteString,
            loadedVideoURL: oldURL,
            phase: .observing(snapshot)
        ) {
            $0.uuid = .incrementing
            $0.videoPlayback.load = { _ in
                throw VideoPlaybackError.notPlayable
            }
        }

        await store.send(.loadSubmitted) {
            $0.phase = .loading(
                requestID: UUID(0),
                lastSnapshot: snapshot
            )
        }
        await store.receive(
            .loadFailed(requestID: UUID(0), error: .notPlayable)
        ) {
            $0.phase = .failed(
                .notPlayable,
                lastSnapshot: snapshot
            )
        }

        #expect(store.state.loadedVideoURL == oldURL)
    }

    @Test
    func secondSubmissionIsIgnoredWhileLoading() async throws {
        let loadCalls = LockIsolated(0)
        let store = makeStore(
            urlText: try VideoTestFixtures.url("video.mp4").absoluteString,
            phase: .loading(
                requestID: UUID(1),
                lastSnapshot: .idle
            )
        ) {
            $0.videoPlayback.load = { _ in
                loadCalls.withValue { $0 += 1 }
            }
        }

        await store.send(.loadSubmitted)

        #expect(loadCalls.value == 0)
    }

    @Test
    func staleLoadCompletionIsIgnored() async throws {
        let store = makeStore(
            urlText: try VideoTestFixtures.url("video.mp4").absoluteString,
            phase: .loading(
                requestID: UUID(2),
                lastSnapshot: .idle
            )
        )

        await store.send(
            .loadSucceeded(
                requestID: UUID(1),
                url: try VideoTestFixtures.url("stale.mp4")
            )
        )
    }

    @Test
    func observationUpdatesSnapshotWithoutReplacingLoadRequest() async throws {
        let snapshot = VideoPlaybackSnapshot(
            status: .loading,
            currentTime: 8
        )
        let store = makeStore(
            urlText: try VideoTestFixtures.url("video.mp4").absoluteString,
            phase: .loading(
                requestID: UUID(1),
                lastSnapshot: .idle
            ),
            observationID: UUID(0)
        )

        await store.send(
            .snapshotReceived(
                observationID: UUID(0),
                snapshot: snapshot
            )
        ) {
            $0.phase = .loading(
                requestID: UUID(1),
                lastSnapshot: snapshot
            )
        }
    }

    @Test
    func taskPublishesControllerSnapshots() async {
        let snapshot = VideoPlaybackSnapshot(
            status: .ready,
            currentTime: 0
        )
        let store = makeStore(urlText: "") {
            $0.uuid = .incrementing
            $0.videoPlayback.playbackSnapshots = {
                AsyncStream { continuation in
                    continuation.yield(snapshot)
                    continuation.finish()
                }
            }
        }

        await store.send(.task) {
            $0.observationID = UUID(0)
        }
        await store.receive(
            .snapshotReceived(
                observationID: UUID(0),
                snapshot: snapshot
            )
        ) {
            $0.phase = .observing(snapshot)
        }
    }

    @Test
    func routeExitCancelsObservation() async {
        let (snapshots, continuation) = AsyncStream<VideoPlaybackSnapshot>.makeStream()
        let store = makeStore(urlText: "") {
            $0.uuid = .incrementing
            $0.videoPlayback.playbackSnapshots = { snapshots }
        }

        await store.send(.task) {
            $0.observationID = UUID(0)
        }
        await store.send(.routeExited) {
            $0.observationID = nil
        }
        await store.finish()
        continuation.finish()
    }

    @Test
    func routeExitCancelsLoadWithoutReportingFailure() async throws {
        let url = try VideoTestFixtures.url("video.mp4")
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let store = makeStore(
            urlText: url.absoluteString
        ) {
            $0.uuid = .incrementing
            $0.videoPlayback.load = { _ in
                startedContinuation.yield()
                try await Task.sleep(for: .seconds(60))
            }
        }

        await store.send(.loadSubmitted) {
            $0.phase = .loading(
                requestID: UUID(0),
                lastSnapshot: .idle
            )
        }
        var startedIterator = started.makeAsyncIterator()
        _ = await startedIterator.next()

        await store.send(.routeExited) {
            $0.phase = .observing(.idle)
        }
        await store.send(
            .loadSucceeded(
                requestID: UUID(0),
                url: url
            )
        )
        await store.finish()
        startedContinuation.finish()
    }

    // MARK: - Helpers

    private func makeStore(
        urlText: String,
        loadedVideoURL: URL? = nil,
        phase: VideoPlaybackFeature.Phase = .observing(.idle),
        observationID: UUID? = nil,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<VideoPlaybackFeature> {
        TestStore(
            initialState: VideoPlaybackFeature.State(
                urlText: urlText,
                loadedVideoURL: loadedVideoURL,
                phase: phase,
                observationID: observationID
            )
        ) {
            VideoPlaybackFeature()
        } withDependencies: {
            configureDependencies(&$0)
        }
    }
}
