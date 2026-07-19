import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackPresentationTests {
    @Test
    func dismissingAndReopeningSheetKeepsPlaybackState() async {
        let song = SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
        let snapshot = MusicPlaybackSnapshot(
            currentItem: song,
            status: .paused,
            currentTime: 42
        )
        let musicPlayback = MusicPlaybackFeature.State(
            selectedSong: song,
            phase: .failed(.playbackFailed, lastSnapshot: snapshot),
            playbackEligibility: .eligible,
            capabilities: .allEnabled
        )
        let state = AppFeature.State(
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
                phase: .loaded([song]),
                providerAccess: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            musicPlayback: musicPlayback,
            isPlayerPresented: true,
            providerSwitch: nil,
            playbackCommand: nil
        )
        let store = TestStore(initialState: state) { AppFeature() }

        await store.send(.setPlayerPresented(false)) {
            $0.isPlayerPresented = false
        }
        await store.send(.setPlayerPresented(true)) {
            $0.isPlayerPresented = true
        }

        #expect(store.state.musicPlayback == musicPlayback)
    }

    @Test
    func barToggleWhilePlayingPausesThroughReducer() async {
        let song = makeSong()
        let (pauseCalled, pauseCalledContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.pause = { pauseCalledContinuation.yield() }
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
            $0.musicProvider.play = { _ in
                playCallCount.withValue { $0 += 1 }
            }
            $0.musicProvider.resume = {
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
                == PlaybackCommandFeature.State(command: .resume(song.id))
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
                phase: .loaded([song]),
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
                capabilities: .allEnabled
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
