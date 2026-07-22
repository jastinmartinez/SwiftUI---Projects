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
        let queue = IdentifiedArray(uniqueElements: [song])
        let playback = PlaybackFeature.State(
            providerID: "fake",
            queue: PlaybackQueueFeature.State(
                songs: queue,
                currentItemID: song.id,
                pendingQueueTransition: nil
            ),
            status: .paused,
            failure: .playbackFailed,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: PlaybackTimelineFeature.State(
                confirmedPosition: 42,
                interaction: .idle
            ),
            pendingOperation: nil,
            pendingReset: nil,
            isPlayerPresented: true
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
            playback: playback,
            providerSwitch: nil
        )
        let store = TestStore(initialState: state) { AppFeature() }

        await store.send(.playback(.setPlayerPresented(false))) {
            $0.playback.isPlayerPresented = false
        }
        await store.send(.playback(.setPlayerPresented(true))) {
            $0.playback.isPlayerPresented = true
        }

        #expect(store.state.playback == playback)
    }

}
