import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPresentationAdapterTests {
    @Test
    func searchHeaderMapsPresentationAndForwardsActions() {
        let actions = LockIsolated<[SearchFeature.Action]>([])
        let store: StoreOf<SearchFeature> = Store(
            initialState: SearchFeature.State(
                query: "vela",
                phase: .idle,
                playbackEligibility: .eligible
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
        let providerSelection = ProviderSelectionView.Model(
            providers: [.appleMusic],
            activeProviderID: .appleMusic,
            isSelectionEnabled: true,
            onSelect: { _ in }
        )
        let model = SearchHeaderView.Model(
            store,
            providerSelection: providerSelection
        )

        #expect(model.query == "vela")
        #expect(model.providerSelection.activeProviderName == "Apple Music")
        #expect(model.isSearchEnabled)

        model.onQueryChanged("")
        model.onSubmit()

        #expect(actions.value == [.queryChanged(""), .submitButtonTapped])
    }

    @Test
    func loadedSongsMapToResultRows() {
        let song = makeSong()
        let store = makeStore(
            query: "result",
            phase: .loaded([song]),
            playbackEligibility: .eligible
        )
        let model = SearchResultsView.Model(store, providerName: "Apple Music")
        let expectedRows = [
            SongRowView.Model(
                songID: song.id,
                title: "Result",
                artistName: "Artist",
                artworkURL: song.artworkURL,
                durationText: "3:35"
            )
        ]

        #expect(
            model.content
                == .results(
                    summary: "1 song · Apple Music",
                    rows: expectedRows
                )
        )
    }

    @Test
    func emptyResultsPreserveTheSubmittedQuery() {
        let store = makeStore(
            query: "No matches",
            phase: .loaded([]),
            playbackEligibility: .eligible
        )
        let model = SearchResultsView.Model(store, providerName: nil)

        #expect(model.content == .empty(query: "No matches"))
    }

    @Test
    func unknownEligibilityVisibilityTracksResultPresence() {
        let resultsStore = makeStore(
            query: "result",
            phase: .loaded([makeSong()]),
            playbackEligibility: .unknown
        )
        let emptyStore = makeStore(
            query: "result",
            phase: .loaded([]),
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
            phase: .failed,
            playbackEligibility: .unknown
        )
        let model = SearchResultsView.Model(store, providerName: nil)

        model.onRetry()

        #expect(store.phase == .idle)
    }

    @Test
    func songTapSelectsLoadedResultThroughReducer() {
        let song = makeSong()
        let appStore = Store(
            initialState: AppFeature.State(
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
                    query: "result",
                    phase: .loaded([song]),
                    playbackEligibility: .eligible
                ),
                musicPlayback: MusicPlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled
                ),
                isPlayerPresented: false,
                pendingProviderID: nil,
                providerSwitchRequestID: nil,
                playbackTransition: nil
            )
        ) {
            AppFeature()
        }
        let searchStore = appStore.scope(state: \.search, action: \.search)
        let model = SearchResultsView.Model(searchStore, providerName: nil)

        model.onSongTapped(song.id)

        #expect(appStore.musicPlayback.selectedSong == song)
        #expect(appStore.isPlayerPresented)
    }

    @Test
    func deniedAndRestrictedPhasesMapToDistinctContent() {
        let deniedModel = SearchResultsView.Model(
            makeStore(
                query: "vela",
                phase: .denied,
                playbackEligibility: .unknown
            ),
            providerName: nil
        )
        #expect(deniedModel.content == .denied)

        let restrictedModel = SearchResultsView.Model(
            makeStore(
                query: "vela",
                phase: .restricted,
                playbackEligibility: .unknown
            ),
            providerName: nil
        )
        #expect(restrictedModel.content == .restricted)
    }

    // MARK: - Helpers

    private func makeStore(
        query: String,
        phase: SearchFeature.Phase,
        playbackEligibility: CatalogPlaybackEligibility
    ) -> StoreOf<SearchFeature> {
        Store(
            initialState: SearchFeature.State(
                query: query,
                phase: phase,
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
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            duration: 215
        )
    }
}
