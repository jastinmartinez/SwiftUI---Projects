import ComposableArchitecture
import Foundation

/// Owns catalog-search input and request state for resolved provider access.
@Reducer
struct SearchFeature {
    @CasePathable
    enum Status: Equatable {
        case idle
        case searching(requestID: UUID)
        case loaded(SearchPaginationFeature.State)
        case failed(MusicProviderError)
    }

    @ObservableState
    struct State: Equatable {
        var query: String
        var status: Status
        var providerAccess: MusicProviderAccess?
    }

    /// Events emitted after search state validates a presentation action.
    enum Delegate: Equatable {
        case songTapped(
            SongSummary,
            loadedResults: IdentifiedArrayOf<SongSummary>
        )
    }

    @CasePathable
    enum Action: Equatable {
        case queryChanged(String)
        case submitButtonTapped
        case retryButtonTapped
        case cancel
        case startSearch(query: String, requestID: UUID)
        case cancelSearch
        case resultTapped(MusicItemID)
        case pagination(SearchPaginationFeature.Action)
        case delegate(Delegate)
        case searchResponse(UUID, Result<SearchPage, MusicProviderError>)
    }

    enum CancelID { case search }

    @Dependency(\.providerSearch) var providerSearch
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Scope(state: \.status, action: \.pagination) {
            EmptyReducer<Status, SearchPaginationFeature.Action>()
                .ifCaseLet(\.loaded, action: \.self) {
                    SearchPaginationFeature()
                }
        }
        Reduce { state, action in
            switch action {
            case .queryChanged(let query):
                state.query = query
                return .send(.cancelSearch)

            case .cancel:
                return .send(.cancelSearch)

            case .submitButtonTapped, .retryButtonTapped:
                guard state.providerAccess?.authorization == .authorized else {
                    return .none
                }
                let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    return .send(.cancelSearch)
                }
                let requestID = uuid()
                return .send(
                    .startSearch(query: query, requestID: requestID)
                )

            case .startSearch(let query, let requestID):
                state.status = .searching(requestID: requestID)
                return .run { send in
                    do {
                        let page = try await providerSearch.searchPage(
                            .initial(query: query),
                            20
                        )
                        await send(.searchResponse(requestID, .success(page)))
                    } catch let error as MusicProviderError {
                        await send(.searchResponse(requestID, .failure(error)))
                    } catch {
                        await send(.searchResponse(requestID, .failure(.network)))
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case .cancelSearch:
                state.status = .idle
                return .merge(
                    .cancel(id: CancelID.search),
                    .cancel(id: SearchPaginationFeature.CancelID.nextPage)
                )

            case .resultTapped(let songID):
                guard case .loaded(let pagination) = state.status,
                    let song = pagination.songs[id: songID]
                else { return .none }
                return .send(
                    .delegate(
                        .songTapped(
                            song,
                            loadedResults: pagination.songs
                        )
                    )
                )

            case .pagination, .delegate:
                return .none

            case .searchResponse(let requestID, .success(let page)):
                guard state.status == .searching(requestID: requestID) else {
                    return .none
                }
                state.status = .loaded(
                    SearchPaginationFeature.State(
                        songs: .init(uniqueElements: page.songs),
                        nextCursor: page.nextCursor,
                        status: .idle
                    )
                )
                return .none

            case .searchResponse(let requestID, .failure(let error)):
                guard state.status == .searching(requestID: requestID) else {
                    return .none
                }
                state.status = .failed(error)
                return .none
            }
        }
    }
}
