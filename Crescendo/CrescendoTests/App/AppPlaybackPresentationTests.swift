import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackPresentationTests {
    @Test
    func dismissingAndReopeningSheetKeepsPlaybackState() async {
        let song = Track(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
        let queue = IdentifiedArray(uniqueElements: [song])
        let playback = PlaybackFeature.State(
            providerID: "fake",
            queue: PlaybackQueueFeature.State(
                tracks: queue,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(queue.ids)),
                currentTrackID: song.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: .paused,
            failureNotice: PlaybackFailureNotice(
                trackID: song.id,
                failure: .playbackFailed
            ),
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: PlaybackTimelineFeature.State(
                confirmedPosition: 42,
                interaction: .idle
            ),
            pendingPlaybackTransition: nil,
            pendingStatusChange: nil,
            pendingProviderReset: nil,
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
                        tracks: [song],
                        nextCursor: nil,
                        status: .idle,
                        providerID: .appleMusic
                    )
                ),
                providerAccess: MusicProviderAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                ),
                providerID: .appleMusic
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
