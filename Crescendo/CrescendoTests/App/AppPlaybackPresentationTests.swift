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
                playbackEligibility: .eligible
            ),
            musicPlayback: musicPlayback,
            isPlayerPresented: true,
            pendingProviderID: nil,
            providerSwitchRequestID: nil,
            playbackStart: nil
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
    func barToggleWhilePausedRequestsPlayThroughReducer() {
        let song = makeSong()
        let store = Store(initialState: makeState(song: song, status: .paused)) {
            AppFeature()
        } withDependencies: {
            $0.musicProvider.play = { _ in }
        }
        let model = NowPlayingBarView.Model(store, song: song)
        #expect(!model.isPlaying)

        model.onTogglePlayPause()

        #expect(
            store.playbackStart
                == PlaybackStartFeature.State(itemID: song.id)
        )
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
                playbackEligibility: .eligible
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
            pendingProviderID: nil,
            providerSwitchRequestID: nil,
            playbackStart: nil
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
