import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackNowPlayingPresentationTests {
    @Test
    func barToggleWhilePlayingPausesThroughReducer() async {
        let song = makeSong(duration: nil)
        let (pauseCalled, pauseCalledContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackTransport.pause = { pauseCalledContinuation.yield() }
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)
        #expect(model.isPlaying)

        model.onTogglePlayPause()

        var pauseCalledIterator = pauseCalled.makeAsyncIterator()
        _ = await pauseCalledIterator.next()
    }

    @Test
    func barToggleProjectsParentOperationPermission() {
        let song = makeSong(duration: nil)
        var state = makeState(song: song, status: .playing)
        state.pendingOperation = .statusChange(
            .init(requestID: UUID(0), target: .paused)
        )
        let store = Store(initialState: state) {
            PlaybackFeature()
        }

        let model = PlaybackNowPlayingView.Model(store, song: song)

        #expect(!model.isPlayEnabled)
        #expect(!model.isPlaying)
    }

    @Test
    func barOpenRoutesPresentationThroughPlayback() {
        let song = makeSong(duration: nil)
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackFeature()
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)

        model.onOpenPlayer()

        #expect(store.isPlayerPresented)
    }

    @Test
    func barToggleWhilePausedResumesWithoutResettingSelection() async {
        let song = makeSong(duration: nil)
        let playCallCount = LockIsolated(0)
        let resumeCallCount = LockIsolated(0)
        let (resumeStarted, resumeStartedContinuation) = AsyncStream<Void>.makeStream()
        let (finishResume, finishResumeContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .paused)) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackQueue.replace = { _, _ in
                playCallCount.withValue { $0 += 1 }
            }
            $0.playbackTransport.play = {
                resumeCallCount.withValue { $0 += 1 }
                resumeStartedContinuation.yield()
                for await _ in finishResume { break }
            }
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)
        #expect(!model.isPlaying)

        model.onTogglePlayPause()

        var resumeStartedIterator = resumeStarted.makeAsyncIterator()
        _ = await resumeStartedIterator.next()
        #expect(store.queue.currentItem == song)
        #expect(playCallCount.value == 0)
        #expect(resumeCallCount.value == 1)

        finishResumeContinuation.yield()
        finishResumeContinuation.finish()
        resumeStartedContinuation.finish()
    }

    @Test
    func compactTimelineUsesSharedSliderWithoutUtilityActions() throws {
        let song = makeSong(duration: 180)
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackFeature()
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)
        let timeline = try #require(model.timeline)

        #expect(timeline.slider.scale == .init(range: 0...180))
        #expect(timeline.controls.isEmpty)
    }

    // MARK: - Helpers

    private func makeState(
        song: SongSummary,
        status: PlaybackStatus
    ) -> PlaybackFeature.State {
        let queue = IdentifiedArray(uniqueElements: [song])
        return PlaybackFeature.State(
            providerID: song.id.providerID,
            queue: PlaybackQueueFeature.State(
                songs: queue,
                currentItemID: song.id
            ),
            status: status,
            failure: nil,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: PlaybackTimelineFeature.State(
                confirmedPosition: 0,
                interaction: .idle
            ),
            pendingOperation: nil,
            pendingReset: nil,
            isPlayerPresented: false
        )
    }

    private func makeSong(duration: TimeInterval?) -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            artworkURL: nil,
            duration: duration
        )
    }
}
