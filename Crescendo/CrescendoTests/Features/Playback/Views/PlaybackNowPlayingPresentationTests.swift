import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackNowPlayingPresentationTests {
    @Test
    func barToggleWhilePlayingPausesThroughReducer() async {
        let song = makeSong()
        let (pauseCalled, pauseCalledContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            AppFeature()
        } withDependencies: {
            $0.playbackControl.pause = { pauseCalledContinuation.yield() }
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)
        #expect(model.isPlaying)

        model.onTogglePlayPause()

        var pauseCalledIterator = pauseCalled.makeAsyncIterator()
        _ = await pauseCalledIterator.next()
    }

    @Test
    func barToggleWhilePausedResumesWithoutResettingSelection() async {
        let song = makeSong()
        let playCallCount = LockIsolated(0)
        let resumeCallCount = LockIsolated(0)
        let (resumeStarted, resumeStartedContinuation) = AsyncStream<Void>.makeStream()
        let (finishResume, finishResumeContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .paused)) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackControl.playQueue = { _, _ in
                playCallCount.withValue { $0 += 1 }
            }
            $0.playbackControl.resume = {
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
        #expect(store.playback.queue.currentItem == song)
        #expect(playCallCount.value == 0)
        #expect(resumeCallCount.value == 1)

        finishResumeContinuation.yield()
        finishResumeContinuation.finish()
        resumeStartedContinuation.finish()
    }

    // MARK: - Helpers

    private func makeState(
        song: SongSummary,
        status: PlaybackStatus
    ) -> AppFeature.State {
        let queue = IdentifiedArray(uniqueElements: [song])
        return AppFeature.State(
            providerConnection: ProviderConnectionFeature.State(
                providers: [.appleMusic],
                connection: .connected(
                    providerID: .appleMusic,
                    access: MusicProviderAccess(
                        authorization: .authorized,
                        playbackEligibility: .eligible
                    )
                )
            ),
            search: SearchFeature.State(
                query: "",
                status: .loaded(
                    SearchPaginationFeature.State(
                        songs: [song],
                        nextCursor: nil,
                        status: .idle
                    )
                ),
                providerAccess: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            playback: PlaybackFeature.State(
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
                pendingOperation: nil
            ),
            isPlayerPresented: false,
            providerSwitch: nil
        )
    }

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
