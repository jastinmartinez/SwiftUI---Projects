import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppReducerTests {
    @Test
    func appTaskStartsPlaybackObservationOnly() async {
        let store = TestStore(initialState: makeState()) {
            AppReducer()
        } withDependencies: {
            $0.playbackObservation = PlaybackObservationClient(
                observations: { AsyncStream { $0.finish() } }
            )
        }

        await store.send(.task)
        await store.receive(.playback(.task))
    }

    @Test
    func switchingTabsChangesOnlyTheSelectedTab() async {
        let libraryItem = makeLibraryItem()
        var state = makeState()
        state.library.library = Library(items: [libraryItem])
        state.library.path = [.songs]
        state.playback.isPlayerPresented = true
        let library = state.library
        let playback = state.playback
        let store = TestStore(initialState: state) {
            AppReducer()
        }

        await store.send(.selectedTabChanged(.library)) {
            $0.selectedTab = .library
        }

        #expect(store.state.library == library)
        #expect(store.state.playback == playback)

        await store.send(.selectedTabChanged(.search)) {
            $0.selectedTab = .search
        }

        #expect(store.state.library == library)
        #expect(store.state.playback == playback)
    }

    private func makeState() -> AppReducer.State {
        AppReducer.State(
            selectedTab: .search,
            search: SearchReducer.State(
                query: "",
                status: .idle,
                providerID: .testProvider
            ),
            library: makeLibraryState(),
            playback: PlaybackReducer.State(
                queue: PlaybackQueueReducer.State(
                    current: nil
                ),
                timeline: PlaybackTimelineReducer.State(
                    confirmedPosition: 0,
                    duration: nil,
                    isSeekable: false,
                    interaction: .idle
                ),
                session: PlaybackSessionReducer.State(
                    status: .idle,
                    pendingStatusChange: nil
                ),
                transition: nil,
                failureNotice: nil,
                isPlayerPresented: false
            )
        )
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

    private func makeLibraryItem() -> Library.Item {
        let track = Track(
            id: .init(providerID: .library, nativeID: "library-track"),
            title: "Library Track",
            artistName: "Artist",
            albumTitle: "Album",
            artworkURL: nil,
            duration: 120,
            playbackURL: URL(fileURLWithPath: "/managed/library-track.m4a")
        )
        return Library.Item(
            track: track,
            contentIdentity: .init(rawValue: "library-content"),
            addedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
    }
}
