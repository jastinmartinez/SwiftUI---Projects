import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct NowPlayingBarPresentationTests {
    @Test
    func barToggleWhilePlayingPausesThroughReducer() async {
        let song = makeSong()
        let (pauseCalled, pauseCalledContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            AppFeature()
        } withDependencies: {
            $0.playbackControl.pause = { pauseCalledContinuation.yield() }
        }
        let model = NowPlayingBarView.Model(store, song: song)
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
            $0.playbackControl.play = { _ in
                playCallCount.withValue { $0 += 1 }
            }
            $0.playbackControl.resume = {
                resumeCallCount.withValue { $0 += 1 }
                resumeStartedContinuation.yield()
                for await _ in finishResume { break }
            }
        }
        let model = NowPlayingBarView.Model(store, song: song)
        #expect(!model.isPlaying)

        model.onTogglePlayPause()

        var resumeStartedIterator = resumeStarted.makeAsyncIterator()
        _ = await resumeStartedIterator.next()
        #expect(
            store.playbackCommand
                == PlaybackCommandFeature.State(
                    command: .resume(song.id),
                    requestID: UUID(0)
                )
        )
        #expect(store.musicPlayback.selectedSong == song)
        #expect(playCallCount.value == 0)
        #expect(resumeCallCount.value == 1)

        finishResumeContinuation.yield()
        finishResumeContinuation.finish()
        resumeStartedContinuation.finish()
    }

    // MARK: - Helpers

    private func makeState(
        song: SongSummary,
        status: MusicPlaybackStatus
    ) -> AppFeature.State {
        AppFeature.State(
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
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: song,
                phase: .observing(
                    MusicPlaybackSnapshot(
                        currentItem: song,
                        status: status,
                        currentTime: 0
                    )
                ),
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: MusicPlaybackTimelineFeature.State(
                    interaction: .idle
                )
            ),
            isPlayerPresented: false,
            providerSwitch: nil,
            playbackCommand: nil
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
