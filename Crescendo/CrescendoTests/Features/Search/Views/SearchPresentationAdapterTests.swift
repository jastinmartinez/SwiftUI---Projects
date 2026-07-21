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
            makeStore(query: " vela ", status: .idle, providerAccess: access),
            providerSelection: makeProviderSelection()
        )
        let emptyQueryModel = SearchHeaderView.Model(
            makeStore(query: "   ", status: .idle, providerAccess: access),
            providerSelection: makeProviderSelection()
        )
        let disconnectedModel = SearchHeaderView.Model(
            makeStore(query: "vela", status: .idle, providerAccess: nil),
            providerSelection: makeProviderSelection()
        )

        #expect(enabledModel.isSearchEnabled)
        #expect(!emptyQueryModel.isSearchEnabled)
        #expect(!disconnectedModel.isSearchEnabled)
    }

    @Test
    func disconnectedProviderShowsRequiresProviderContent() {
        let model = SearchResultsView.Model(
            makeStore(query: "vela", status: .failed(.network), providerAccess: nil),
            providerName: nil
        )

        #expect(model.content == .requiresProvider)
    }

    @Test
    func requiresProviderTakesPrecedenceOverSearchPhase() {
        let model = SearchResultsView.Model(
            makeStore(
                query: "vela",
                status: loadedStatus(songs: [makeSong()]),
                providerAccess: nil
            ),
            providerName: nil
        )

        #expect(model.content == .requiresProvider)
    }

    @Test
    func loadedSongsMapToResultRows() {
        let song = makeSong()
        let store = makeStore(
            query: "result",
            status: loadedStatus(songs: [song]),
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
            status: loadedStatus(songs: [makeSong()]),
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
        status: SearchFeature.Status,
        providerAccess: MusicProviderAccess?
    ) -> StoreOf<SearchFeature> {
        Store(
            initialState: SearchFeature.State(
                query: query,
                status: status,
                providerAccess: providerAccess
            )
        ) {
            SearchFeature()
        }
    }

    private func loadedStatus(songs: [SongSummary]) -> SearchFeature.Status {
        .loaded(
            SearchPaginationFeature.State(
                songs: .init(uniqueElements: songs),
                nextCursor: nil,
                status: .idle
            )
        )
    }

    private func makeProviderSelection() -> ProviderSelectionView.Model {
        let provider = ProviderDescriptor.appleMusic

        return ProviderSelectionView.Model(
            status: .connected(providerName: provider.name),
            collapsedIcon: .appleMusic,
            collapsedLabel: provider.name,
            menuTitle: Locs.ProviderSelection.menuTitle,
            providerRows: [
                .init(
                    id: provider.id,
                    label: provider.name,
                    statusLabel: nil,
                    isSelected: true,
                    isEnabled: true,
                    onSelect: {}
                )
            ],
            recoveryAction: nil,
            isSelectionEnabled: true,
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
