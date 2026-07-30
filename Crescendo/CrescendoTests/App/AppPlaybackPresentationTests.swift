import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackPresentationTests {
    @Test
    func dismissingAndReopeningFullScreenPlayerKeepsPlaybackState() async throws {
        let song = Track(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
        let queue = IdentifiedArray(uniqueElements: [song])
        let confirmed = try #require(
            PlaybackQueue(tracks: queue, startingAt: song.id)
        )
        let playback = PlaybackReducer.State(
            queue: PlaybackQueueReducer.State(
                current: confirmed
            ),
            timeline: PlaybackTimelineReducer.State(
                confirmedPosition: 42,
                duration: nil,
                isSeekable: false,
                interaction: .idle
            ),
            session: PlaybackSessionReducer.State(
                status: .paused,
                pendingStatusChange: nil
            ),
            transition: nil,
            failureNotice: PlaybackFailureNotice(
                trackID: song.id,
                failure: .playbackFailed
            ),
            isPlayerPresented: true
        )
        let state = AppReducer.State(
            search: SearchReducer.State(
                query: "",
                status: .loaded(
                    SearchPaginationReducer.State(
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
        let store = TestStore(initialState: state) { AppReducer() }

        await store.send(.playback(.setPlayerPresented(false))) {
            $0.playback.isPlayerPresented = false
        }
        await store.send(.playback(.setPlayerPresented(true))) {
            $0.playback.isPlayerPresented = true
        }

        #expect(store.state.playback == playback)
    }

}
