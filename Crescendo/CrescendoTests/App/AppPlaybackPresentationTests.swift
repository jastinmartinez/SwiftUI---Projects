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
            artworkURL: nil
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
            registeredProviders: [.appleMusic],
            activeProviderID: "apple-music",
            search: SearchFeature.State(
                query: "",
                phase: .loaded([song]),
                playbackEligibility: .eligible
            ),
            musicPlayback: musicPlayback,
            isPlayerPresented: true,
            pendingProviderID: nil,
            providerSwitchRequestID: nil,
            playbackTransition: nil
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
    func barToggleChoosesTransportActionFromPlayingState() {
        #expect(NowPlayingBarView.Model.toggleAction(isPlaying: true) == .pauseTapped)
        #expect(NowPlayingBarView.Model.toggleAction(isPlaying: false) == .playTapped)
    }
}
