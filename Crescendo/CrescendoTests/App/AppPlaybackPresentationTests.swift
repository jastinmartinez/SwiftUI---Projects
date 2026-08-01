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
            selectedTab: .search,
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
            library: makeLibraryState(),
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

    @Test
    func switchingTabsKeepsCompactAndFullPlayerPresentation() async throws {
        let song = Track(
            id: .init(providerID: "fake", nativeID: "presentation"),
            title: "Song",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
        let confirmed = try #require(
            PlaybackQueue(
                tracks: [song],
                startingAt: song.id
            )
        )
        let playback = PlaybackReducer.State(
            queue: .init(current: confirmed),
            timeline: .init(
                confirmedPosition: 30,
                duration: 120,
                isSeekable: true,
                interaction: .idle
            ),
            session: .init(status: .playing, pendingStatusChange: nil),
            transition: nil,
            failureNotice: nil,
            isPlayerPresented: true
        )
        let store = TestStore(
            initialState: AppReducer.State(
                selectedTab: .search,
                search: SearchReducer.State(
                    query: "",
                    status: .idle,
                    providerID: .testProvider
                ),
                library: makeLibraryState(),
                playback: playback
            )
        ) {
            AppReducer()
        }

        await store.send(.selectedTabChanged(.library)) {
            $0.selectedTab = .library
        }
        #expect(store.state.playback == playback)
        #expect(store.state.playback.queue.current?.currentTrack == song)
        #expect(store.state.playback.isPlayerPresented)

        await store.send(.selectedTabChanged(.search)) {
            $0.selectedTab = .search
        }
        #expect(store.state.playback == playback)
    }

    private func makeLibraryState() -> LibraryReducer.State {
        LibraryReducer.State(
            library: Library(items: []),
            catalog: .init(entries: []),
            loadStatus: .idle,
            path: [],
            isFileImporterPresented: false,
            recovery: nil,
            importBatch: nil,
            fileSelectionFailure: nil
        )
    }
}
