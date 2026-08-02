import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct SearchPresentationAdapterTests {
    @Test
    func searchHeaderRequiresOnlyANonemptyTrimmedQuery() {
        let enabled = SearchHeaderView.Model(
            makeSearchStore(query: " vela ")
        )
        let disabled = SearchHeaderView.Model(
            makeSearchStore(query: "   ")
        )

        #expect(enabled.isSearchEnabled)
        #expect(!disabled.isSearchEnabled)
    }

    @Test
    func providerRailsUseLocalizedProviderPresentation() {
        let library = ProviderSearchRailView.Model(
            makeRailStore(providerID: .library)
        )
        let jamendo = ProviderSearchRailView.Model(
            makeRailStore(providerID: .jamendo)
        )

        #expect(library.id == .library)
        #expect(library.title == Locs.Search.Provider.library)
        #expect(jamendo.id == .jamendo)
        #expect(jamendo.title == Locs.Search.Provider.jamendo)
        #expect(library.strings.seeAll == Locs.Search.Provider.seeAll)
        #expect(library.strings.searching == Locs.Search.searching)
        #expect(
            library.strings.localEmptyTitle
                == Locs.Search.Provider.localEmptyTitle
        )
        #expect(
            library.strings.localEmptyMessage
                == Locs.Search.Provider.localEmptyMessage
        )
        #expect(
            library.strings.openLibrary
                == Locs.Search.Provider.openLibrary
        )
        #expect(library.strings.failure == Locs.Search.Provider.failure)
        #expect(library.strings.retry == Locs.Common.retry)
    }

    @Test
    func loadedRailProjectsFiveRowsAndPreservesTheFullFirstPage() throws {
        let tracks = (1...20).map { makeTrack(nativeID: String($0)) }
        let status = loadedRailStatus(
            tracks: tracks,
            nextCursor: SearchCursor(value: "page-2")
        )
        let store = makeRailStore(
            providerID: .jamendo,
            status: status
        )

        let rows = try loadedRows(
            from: ProviderSearchRailView.Model(store)
        )

        #expect(rows.map(\.id) == tracks.prefix(5).map(\.id))
        #expect(rows.allSatisfy { $0.accessory == .none })
        #expect(rows.allSatisfy { $0.durationText == nil })
        guard case .loaded(let page) = store.status else {
            Issue.record("Expected the reducer to retain its loaded page")
            return
        }
        #expect(page.tracks.map(\.id) == tracks.map(\.id))
        #expect(page.nextCursor == SearchCursor(value: "page-2"))
    }

    @Test
    func railMapsMutuallyExclusiveLifecycleContent() {
        let inactive = ProviderSearchRailView.Model(
            makeRailStore(providerID: .jamendo, status: .inactive)
        )
        let searching = ProviderSearchRailView.Model(
            makeRailStore(
                providerID: .jamendo,
                status: .searching(requestID: UUID(0))
            )
        )
        let failed = ProviderSearchRailView.Model(
            makeRailStore(providerID: .jamendo, status: .failed(.network))
        )

        #expect(inactive.content == .inactive)
        #expect(searching.content == .loading)
        #expect(failed.content == .failed)
    }

    @Test
    func onlyTheLocalEmptyRailOffersTheLibraryAction() {
        let library = ProviderSearchRailView.Model(
            makeRailStore(
                providerID: .library,
                status: loadedRailStatus(tracks: [], nextCursor: nil)
            )
        )
        let jamendo = ProviderSearchRailView.Model(
            makeRailStore(
                providerID: .jamendo,
                status: loadedRailStatus(tracks: [], nextCursor: nil)
            )
        )

        #expect(library.content == .empty(showsLibraryAction: true))
        #expect(jamendo.content == .empty(showsLibraryAction: false))
    }

    @Test
    func railCallbacksSendTheCorrespondingChildActions() {
        let track = makeTrack()
        let actions = LockIsolated<[ProviderSearchReducer.Action]>([])
        let model = ProviderSearchRailView.Model(
            makeRailStore(
                providerID: .library,
                status: loadedRailStatus(tracks: [track], nextCursor: nil),
                actions: actions
            )
        )

        model.onAppear()
        model.onRetry()
        model.onSeeAll()
        model.onOpenLibrary()
        model.onTrackTapped(track.id)

        #expect(
            actions.value == [
                .railBecameVisible,
                .retryButtonTapped,
                .seeAllButtonTapped,
                .libraryButtonTapped,
                .resultTapped(track.id),
            ]
        )
    }

    @Test
    func destinationProjectsEveryTrackAndOnlyOneContinuationTrigger() {
        let tracks = (1...20).map { makeTrack(nativeID: String($0)) }
        let model = SearchResultListView.Model(
            makeResultsStore(
                providerID: .jamendo,
                tracks: tracks,
                nextCursor: SearchCursor(value: "page-2")
            )
        )

        #expect(model.rows.map(\.id) == tracks.map(\.id))
        let expectedTriggers: [String?] =
            Array(repeating: nil, count: 19) + ["page-2"]
        #expect(model.rows.map(\.paginationTriggerID) == expectedTriggers)
        #expect(model.rows.allSatisfy { $0.song.durationText == nil })
        #expect(model.footer.content == .hidden)
    }

    @Test
    func destinationMapsContinuationLifecycleIntoTheFooter() {
        let cursor = SearchCursor(value: "page-2")
        let hiddenWithoutCursor = SearchResultListView.Model(
            makeResultsStore(nextCursor: nil, status: .idle)
        )
        let hiddenWithCursor = SearchResultListView.Model(
            makeResultsStore(nextCursor: cursor, status: .idle)
        )
        let loading = SearchResultListView.Model(
            makeResultsStore(
                nextCursor: cursor,
                status: .loading(requestID: UUID(0))
            )
        )
        let failed = SearchResultListView.Model(
            makeResultsStore(
                nextCursor: cursor,
                status: .failed(.network)
            )
        )

        #expect(hiddenWithoutCursor.footer.content == .hidden)
        #expect(hiddenWithCursor.footer.content == .hidden)
        #expect(loading.footer.content == .loading)
        #expect(failed.footer.content == .failed)
    }

    @Test
    func destinationCallbacksSendOnlyDestinationActions() {
        let track = makeTrack()
        let actions = LockIsolated<[ProviderSearchResultsReducer.Action]>([])
        let model = SearchResultListView.Model(
            makeResultsStore(
                tracks: [track],
                nextCursor: SearchCursor(value: "page-2"),
                actions: actions
            )
        )

        model.onLoadNextPage()
        model.footer.onRetry()
        model.onTrackTapped(track.id)

        #expect(
            actions.value == [
                .nextPageRequested,
                .retryButtonTapped,
                .resultTapped(track.id),
            ]
        )
    }

    @Test
    func destinationTrackWithoutAnArtistUsesLocalizedFallback() {
        let track = Track(
            id: .init(providerID: .library, nativeID: "library"),
            title: "Library Track",
            artistName: nil,
            albumTitle: nil,
            artworkURL: nil,
            duration: nil
        )
        let model = SearchResultListView.Model(
            makeResultsStore(providerID: .library, tracks: [track])
        )

        #expect(
            model.rows.first?.song.artistName
                == Locs.Common.unknownArtist
        )
    }
}

private extension SearchPresentationAdapterTests {
    func makeSearchStore(query: String) -> StoreOf<SearchReducer> {
        Store(
            initialState: SearchReducer.State(
                query: query,
                providerIDs: [.library, .jamendo]
            )
        ) {
            SearchReducer()
        }
    }

    func makeRailStore(
        providerID: ProviderID,
        status: ProviderSearchReducer.Status = .inactive,
        actions: LockIsolated<[ProviderSearchReducer.Action]>? = nil
    ) -> StoreOf<ProviderSearchReducer> {
        Store(
            initialState: ProviderSearchReducer.State(
                providerID: providerID,
                status: status
            )
        ) {
            Reduce { _, action in
                actions?.withValue { $0.append(action) }
                return .none
            }
        }
    }

    func loadedRailStatus(
        tracks: [Track],
        nextCursor: SearchCursor?
    ) -> ProviderSearchReducer.Status {
        .loaded(
            ProviderSearchReducer.Page(
                tracks: .init(uniqueElements: tracks),
                nextCursor: nextCursor
            )
        )
    }

    func loadedRows(
        from model: ProviderSearchRailView.Model
    ) throws -> [TrackRowView.Model] {
        guard case .loaded(let rows) = model.content else {
            throw TestFailure.expectedLoadedRail
        }
        return rows
    }

    func makeResultsStore(
        providerID: ProviderID = .testProvider,
        tracks: [Track]? = nil,
        nextCursor: SearchCursor? = nil,
        status: ProviderSearchResultsReducer.Status = .idle,
        actions: LockIsolated<[ProviderSearchResultsReducer.Action]>? = nil
    ) -> StoreOf<ProviderSearchResultsReducer> {
        Store(
            initialState: ProviderSearchResultsReducer.State(
                providerID: providerID,
                query: "frozen query",
                tracks: .init(uniqueElements: tracks ?? [makeTrack()]),
                nextCursor: nextCursor,
                status: status
            )
        ) {
            Reduce { _, action in
                actions?.withValue { $0.append(action) }
                return .none
            }
        }
    }

    func makeTrack(nativeID: String = "1") -> Track {
        Track(
            id: .init(providerID: .testProvider, nativeID: nativeID),
            title: "Result \(nativeID)",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            duration: 215
        )
    }
}

private enum TestFailure: Error {
    case expectedLoadedRail
}
