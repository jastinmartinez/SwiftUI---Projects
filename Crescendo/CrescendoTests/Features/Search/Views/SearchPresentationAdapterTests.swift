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

        guard case .requiresProvider = model.content else {
            Issue.record("Expected provider connection content")
            return
        }
    }

    @Test
    func requiresProviderTakesPrecedenceOverSearchStatus() {
        let model = SearchResultsView.Model(
            makeStore(
                query: "vela",
                status: loadedStatus(
                    songs: [makeSong()],
                    nextCursor: nil,
                    paginationStatus: .idle
                ),
                providerAccess: nil
            ),
            providerName: nil
        )

        guard case .requiresProvider = model.content else {
            Issue.record("Expected provider connection content")
            return
        }
    }

    @Test
    func loadedSongsMapToResultRows() {
        let song = makeSong()
        let store = makeStore(
            query: "result",
            status: loadedStatus(
                songs: [song],
                nextCursor: SearchCursor(value: "next"),
                paginationStatus: .idle
            ),
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

        guard case .results(let summary, let rows, let footer) = model.content else {
            Issue.record("Expected loaded results")
            return
        }

        #expect(summary == "1 song · Apple Music")
        #expect(rows == expectedRows)
        #expect(footer.content == .ready(triggerID: "next"))
        #expect(
            footer.strings
                == SearchPaginationFooterView.Model.Strings(
                    loading: "Loading more songs",
                    failure: "More songs couldn’t be loaded.",
                    retry: "Retry"
                )
        )
    }

    @Test
    func loadedPaginationMapsFooterPresentation() throws {
        let cursor = SearchCursor(value: "next")
        let hidden = makeResultsModel(
            nextCursor: nil,
            paginationStatus: .idle
        )
        let ready = makeResultsModel(
            nextCursor: cursor,
            paginationStatus: .idle
        )
        let loading = makeResultsModel(
            nextCursor: cursor,
            paginationStatus: .loading(requestID: UUID(0))
        )
        let failed = makeResultsModel(
            nextCursor: cursor,
            paginationStatus: .failed(.network)
        )

        #expect(try footer(from: hidden).content == .hidden)
        #expect(
            try footer(from: ready).content
                == .ready(triggerID: cursor.value)
        )
        #expect(try footer(from: loading).content == .loading)
        #expect(try footer(from: failed).content == .failed)
    }

    @Test(arguments: [
        SearchPaginationFeature.Status.idle,
        .failed(.network),
    ])
    func footerCallbackStartsTheExpectedPageRequest(
        paginationStatus: SearchPaginationFeature.Status
    ) throws {
        let store = Store(
            initialState: SearchFeature.State(
                query: "result",
                status: loadedStatus(
                    songs: [makeSong()],
                    nextCursor: SearchCursor(value: "next"),
                    paginationStatus: paginationStatus
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearch.searchPage = { request, _ in
                #expect(
                    request
                        == .continuation(SearchCursor(value: "next"))
                )
                return try await Task.never()
            }
        }
        let model = SearchResultsView.Model(
            store,
            providerName: "Apple Music"
        )
        let footer = try footer(from: model)

        switch paginationStatus {
        case .idle:
            footer.onLoadNextPage()
        case .failed:
            footer.onRetry()
        case .loading:
            Issue.record("This test covers only actionable footer states")
        }

        guard case .loaded(let pagination) = store.status else {
            Issue.record("Expected loaded pagination state")
            return
        }
        #expect(pagination.status == .loading(requestID: UUID(0)))
    }

    @Test
    func ineligibleAccessStillShowsSubscriptionNoticeForResults() {
        let store = makeStore(
            query: "result",
            status: loadedStatus(
                songs: [makeSong()],
                nextCursor: nil,
                paginationStatus: .idle
            ),
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

    private func loadedStatus(
        songs: [SongSummary],
        nextCursor: SearchCursor?,
        paginationStatus: SearchPaginationFeature.Status
    ) -> SearchFeature.Status {
        .loaded(
            SearchPaginationFeature.State(
                songs: .init(uniqueElements: songs),
                nextCursor: nextCursor,
                status: paginationStatus
            )
        )
    }

    private func makeResultsModel(
        nextCursor: SearchCursor?,
        paginationStatus: SearchPaginationFeature.Status
    ) -> SearchResultsView.Model {
        SearchResultsView.Model(
            makeStore(
                query: "result",
                status: loadedStatus(
                    songs: [makeSong()],
                    nextCursor: nextCursor,
                    paginationStatus: paginationStatus
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            providerName: "Apple Music"
        )
    }

    private func footer(
        from model: SearchResultsView.Model
    ) throws -> SearchPaginationFooterView.Model {
        guard case .results(_, _, let footer) = model.content else {
            throw TestFailure.expectedLoadedResults
        }
        return footer
    }

    private func makeProviderSelection() -> ProviderSelectionView.Model {
        let provider = ProviderDescriptor.appleMusic

        return ProviderSelectionView.Model(
            status: .connected(providerName: provider.name),
            activeProviderName: provider.name,
            connectedProviderName: provider.name,
            collapsedIcon: .appleMusic,
            collapsedLabel: provider.name,
            accessibilityValue: provider.name,
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

private enum TestFailure: Error {
    case expectedLoadedResults
}
