import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPresentationAdapterTests {
    @Test
    func searchHeaderRequiresOnlyANonemptyTrimmedQuery() {
        let enabled = SearchHeaderView.Model(
            makeStore(query: " vela ", status: .idle, providerAccess: nil),
            providerSelection: makeProviderSelection()
        )
        let disabled = SearchHeaderView.Model(
            makeStore(query: "   ", status: .idle, providerAccess: nil),
            providerSelection: makeProviderSelection()
        )

        #expect(enabled.isSearchEnabled)
        #expect(!disabled.isSearchEnabled)
    }

    @Test
    func loadedResultsRemainVisibleWithoutProviderAccess() {
        let track = makeTrack()
        let model = SearchResultsView.Model(
            makeStore(
                query: "vela",
                status: loadedStatus(
                    tracks: [track],
                    nextCursor: nil,
                    paginationStatus: .idle
                ),
                providerAccess: nil
            ),
            providerName: "Jamendo"
        )

        guard case .results(let results) = model.content else {
            Issue.record("Expected loaded results")
            return
        }
        #expect(results.rows.map(\.id) == [track.id])
    }

    @Test
    func loadedSongsMapToResultRows() {
        let song = makeTrack()
        let store = makeStore(
            query: "result",
            status: loadedStatus(
                tracks: [song],
                nextCursor: SearchCursor(value: "next"),
                paginationStatus: .idle
            ),
            providerAccess: makeAccess(
                authorization: .authorized,
                playbackEligibility: .eligible
            )
        )
        let model = SearchResultsView.Model(store, providerName: "Test Provider")
        let expectedRows = [
            SearchResultListView.Model.Row(
                id: song.id,
                song: TrackRowView.Model(
                    id: song.id,
                    title: "Result",
                    artistName: "Artist",
                    artworkURL: song.artworkURL,
                    durationText: "3:35",
                    accessory: .disclosure
                ),
                paginationTriggerID: "next"
            )
        ]

        guard case .results(let results) = model.content else {
            Issue.record("Expected loaded results")
            return
        }

        #expect(results.summary == "1 song · Test Provider")
        #expect(results.rows == expectedRows)
        #expect(results.footer.content == .hidden)
        let expectedStrings = SearchPaginationFooterView.Model.Strings(
            loading: "Loading more songs",
            failure: "More songs couldn’t be loaded.",
            retry: "Retry"
        )
        #expect(results.footer.strings == expectedStrings)
    }

    @Test
    func nextPageTriggerMapsOnlyToLastResultRow() {
        let firstSong = makeTrack()
        let lastSong = Track(
            id: .init(providerID: "fake", nativeID: "2"),
            title: "Last result",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: URL(string: "https://example.com/last-artwork.jpg"),
            duration: 180
        )
        let model = SearchResultsView.Model(
            makeStore(
                query: "result",
                status: loadedStatus(
                    tracks: [firstSong, lastSong],
                    nextCursor: SearchCursor(value: "next"),
                    paginationStatus: .idle
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            providerName: "Test Provider"
        )

        guard case .results(let results) = model.content else {
            Issue.record("Expected loaded results")
            return
        }

        #expect(results.rows.map(\.paginationTriggerID) == [nil, "next"])
        #expect(results.footer.content == .hidden)
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
        #expect(try footer(from: ready).content == .hidden)
        #expect(try footer(from: loading).content == .loading)
        #expect(try footer(from: failed).content == .failed)
    }

    @Test(arguments: [
        SearchPaginationFeature.Status.idle,
        .failed(.network),
    ])
    func paginationCallbackStartsTheExpectedPageRequest(
        paginationStatus: SearchPaginationFeature.Status
    ) throws {
        let store = Store(
            initialState: SearchFeature.State(
                query: "result",
                status: loadedStatus(
                    tracks: [makeTrack()],
                    nextCursor: SearchCursor(value: "next"),
                    paginationStatus: paginationStatus
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                ),
                providerID: .testProvider
            )
        ) {
            SearchFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    .testProvider: ProviderSearchClient(
                        searchPage: { request, _ in
                            let expectedRequest = SearchPageRequest.continuation(
                                SearchCursor(value: "next")
                            )
                            #expect(request == expectedRequest)
                            return try await Task.never()
                        }
                    )
                ]
            )
        }
        let model = SearchResultsView.Model(
            store,
            providerName: "Test Provider"
        )
        let results = try results(from: model)

        switch paginationStatus {
        case .idle:
            results.onLoadNextPage()
        case .failed:
            results.footer.onRetry()
        case .loading:
            Issue.record("This test covers only actionable footer states")
        }

        guard case .loaded(let pagination) = store.status else {
            Issue.record("Expected loaded pagination state")
            return
        }
        #expect(pagination.status == .loading(requestID: UUID(0)))
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
                providerAccess: providerAccess,
                providerID: .testProvider
            )
        ) {
            SearchFeature()
        }
    }

    private func loadedStatus(
        tracks: [Track],
        nextCursor: SearchCursor?,
        paginationStatus: SearchPaginationFeature.Status
    ) -> SearchFeature.Status {
        .loaded(
            SearchPaginationFeature.State(
                tracks: .init(uniqueElements: tracks),
                nextCursor: nextCursor,
                status: paginationStatus,
                providerID: .testProvider
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
                    tracks: [makeTrack()],
                    nextCursor: nextCursor,
                    paginationStatus: paginationStatus
                ),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            providerName: "Test Provider"
        )
    }

    private func footer(
        from model: SearchResultsView.Model
    ) throws -> SearchPaginationFooterView.Model {
        try results(from: model).footer
    }

    private func results(
        from model: SearchResultsView.Model
    ) throws -> SearchResultListView.Model {
        guard case .results(let results) = model.content else {
            throw TestFailure.expectedLoadedResults
        }
        return results
    }

    private func makeProviderSelection() -> ProviderSelectionView.Model {
        let provider = ProviderDescriptor.testProvider

        return ProviderSelectionView.Model(
            status: .connected(providerName: provider.name),
            activeProviderName: provider.name,
            connectedProviderName: provider.name,
            collapsedIcon: .generic,
            collapsedLabel: provider.name,
            accessibilityValue: provider.name,
            menuTitle: Locs.ProviderSelection.menuTitle,
            providerRows: [
                .init(
                    id: provider.id,
                    icon: .generic,
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

    private func makeTrack() -> Track {
        Track(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Result",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            duration: 215
        )
    }
}

private enum TestFailure: Error {
    case expectedLoadedResults
}
