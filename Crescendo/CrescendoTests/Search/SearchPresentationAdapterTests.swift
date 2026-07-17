import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPresentationAdapterTests {
    @Test
    func searchHeaderRequiresAuthorizedAccessAndTrimmedQuery() {
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let enabledModel = SearchHeaderView.Model(
            makeStore(query: " vela ", phase: .idle, providerAccess: access),
            providerSelection: makeProviderSelection()
        )
        let emptyQueryModel = SearchHeaderView.Model(
            makeStore(query: "   ", phase: .idle, providerAccess: access),
            providerSelection: makeProviderSelection()
        )
        let disconnectedModel = SearchHeaderView.Model(
            makeStore(query: "vela", phase: .idle, providerAccess: nil),
            providerSelection: makeProviderSelection()
        )

        #expect(enabledModel.isSearchEnabled)
        #expect(!emptyQueryModel.isSearchEnabled)
        #expect(!disconnectedModel.isSearchEnabled)
    }

    @Test
    func disconnectedProviderShowsRequiresProviderContent() {
        let model = SearchResultsView.Model(
            makeStore(query: "vela", phase: .failed, providerAccess: nil),
            providerName: nil
        )

        #expect(model.content == .requiresProvider)
    }

    @Test
    func requiresProviderTakesPrecedenceOverSearchPhase() {
        let model = SearchResultsView.Model(
            makeStore(query: "vela", phase: .loaded([makeSong()]), providerAccess: nil),
            providerName: nil
        )

        #expect(model.content == .requiresProvider)
    }

    @Test
    func loadedSongsMapToResultRows() {
        let song = makeSong()
        let store = makeStore(
            query: "result",
            phase: .loaded([song]),
            providerAccess: makeAccess(
                authorization: .authorized,
                playbackEligibility: .eligible
            )
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
    func ineligibleAccessStillShowsSubscriptionNoticeForResults() {
        let store = makeStore(
            query: "result",
            phase: .loaded([makeSong()]),
            providerAccess: makeAccess(
                authorization: .authorized,
                playbackEligibility: .ineligible
            )
        )

        #expect(
            PlaybackEligibilityNoticeView.Model(store).presentation
                == .subscriptionRequired
        )
    }

    // MARK: - Helpers

    private func makeStore(
        query: String,
        phase: SearchFeature.Phase,
        providerAccess: MusicProviderAccess?
    ) -> StoreOf<SearchFeature> {
        Store(
            initialState: SearchFeature.State(
                query: query,
                phase: phase,
                providerAccess: providerAccess
            )
        ) {
            SearchFeature()
        }
    }

    private func makeProviderSelection() -> ProviderSelectionView.Model {
        ProviderSelectionView.Model(
            providers: [.appleMusic],
            activeProviderID: .appleMusic,
            isSelectionEnabled: true,
            onSelect: { _ in }
        )
    }

    private func makeAccess(
        authorization: MusicAuthorizationStatus,
        playbackEligibility: CatalogPlaybackEligibility
    ) -> MusicProviderAccess {
        MusicProviderAccess(
            authorization: authorization,
            playbackEligibility: playbackEligibility
        )
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
