import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct SearchPresentationAdapterTests {
    @Test
    func loadedSongsMapToResultRows() {
        let song = makeSong()
        let store = makeStore(
            query: "result",
            status: .loaded([song]),
            playbackEligibility: .eligible
        )
        let model = SearchResultsView.Model(store)
        let expectedRows = [
            SongRowView.Model(
                songID: song.id,
                title: "Result",
                artistName: "Artist"
            )
        ]

        #expect(model.content == .results(expectedRows))
    }

    @Test
    func emptyResultsPreserveTheSubmittedQuery() {
        let store = makeStore(
            query: "No matches",
            status: .loaded([]),
            playbackEligibility: .eligible
        )
        let model = SearchResultsView.Model(store)

        #expect(model.content == .empty(query: "No matches"))
    }

    @Test
    func unknownEligibilityVisibilityTracksResultPresence() {
        let resultsStore = makeStore(
            query: "result",
            status: .loaded([makeSong()]),
            playbackEligibility: .unknown
        )
        let emptyStore = makeStore(
            query: "result",
            status: .loaded([]),
            playbackEligibility: .unknown
        )
        let resultsModel = PlaybackEligibilityNoticeView.Model(resultsStore)
        let emptyModel = PlaybackEligibilityNoticeView.Model(emptyStore)

        #expect(resultsModel.presentation == .availabilityUnknown)
        #expect(emptyModel.presentation == .hidden)
    }

    @Test
    func retryForwardsToTheSearchReducer() {
        let store = makeStore(
            query: "",
            status: .failed,
            playbackEligibility: .unknown
        )
        let model = SearchResultsView.Model(store)

        model.onRetry()

        #expect(store.status == .idle)
    }

    @Test
    func songTapForwardsSelectedSummaryToTheAppReducer() {
        let song = makeSong()
        let appStore = Store(
            initialState: AppFeature.State(
                registeredProviders: [.appleMusic],
                activeProviderID: "apple-music",
                search: SearchFeature.State(
                    query: "result",
                    status: .loaded([song]),
                    playbackEligibility: .eligible
                ),
                musicPlayback: MusicPlaybackFeature.State(
                    selectedSong: nil,
                    status: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled
                ),
                isPlayerPresented: false
            )
        ) {
            AppFeature()
        }
        let searchStore = appStore.scope(state: \.search, action: \.search)
        let model = SearchResultsView.Model(searchStore)

        model.onSongTapped(song.id)

        #expect(appStore.musicPlayback.selectedSong == song)
        #expect(appStore.isPlayerPresented)
    }

    // MARK: - Helpers

    private func makeStore(
        query: String,
        status: SearchFeature.Status,
        playbackEligibility: CatalogPlaybackEligibility
    ) -> StoreOf<SearchFeature> {
        Store(
            initialState: SearchFeature.State(
                query: query,
                status: status,
                playbackEligibility: playbackEligibility
            )
        ) {
            SearchFeature()
        }
    }

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Result",
            artistName: "Artist",
            artworkURL: nil
        )
    }
}
