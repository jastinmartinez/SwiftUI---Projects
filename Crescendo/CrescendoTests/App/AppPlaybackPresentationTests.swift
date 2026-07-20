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
            capabilities: .allEnabled,
            timeline: MusicPlaybackTimelineFeature.State(
                interaction: .idle
            )
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

}
