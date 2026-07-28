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
            timeline: PlaybackTimelineFeature.State(
                confirmedPosition: 42,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            ),
            pendingPlaybackTransition: nil,
            pendingStatusChange: nil,
            isPlayerPresented: true
        )
        let state = AppFeature.State(
            search: SearchFeature.State(
                query: "",
                status: .loaded(
                    SearchPaginationFeature.State(
                        tracks: [song],
                        nextCursor: nil,
                        status: .idle,
                        providerID: .testProvider
                    )
                ),
                providerID: .testProvider
            ),
            playback: playback
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
