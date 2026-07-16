import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackPresentationTests {
    @Test
    func dismissingSheetKeepsPlaybackState() async {
        let song = SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            artworkURL: nil
        )
        let state = AppFeature.State(
            registeredProviders: [.appleMusic],
            activeProviderID: "apple-music",
            search: SearchFeature.State(
                query: "",
                phase: .loaded([song]),
                playbackEligibility: .eligible
            ),
            musicPlayback: MusicPlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: .allEnabled
            ),
            isPlayerPresented: false
        )
        let store = TestStore(initialState: state) { AppFeature() }

        await store.send(.search(.resultTapped(song.id)))
        await store.receive(.search(.delegate(.songSelected(song)))) {
            $0.musicPlayback.selectedSong = song
            $0.musicPlayback.playbackEligibility = .eligible
            $0.isPlayerPresented = true
        }
        await store.send(.setPlayerPresented(false)) {
            $0.isPlayerPresented = false
        }
        #expect(store.state.musicPlayback.selectedSong == song)
        #expect(store.state.musicPlayback.phase == .observing(.idle))
    }
}
