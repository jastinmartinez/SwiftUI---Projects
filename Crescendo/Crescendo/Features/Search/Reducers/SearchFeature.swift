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

        var pagination: SearchPaginationFeature.State? {
            get {
                guard case .loaded(let pagination) = status else { return nil }
                return pagination
            }
            set {
                guard let newValue else {
                    if case .loaded = status {
                        status = .idle
                    }
                    return
                }
                status = .loaded(newValue)
            }
        }
    }

    /// Events emitted after search state validates a presentation action.
    enum Delegate: Equatable {
        case songTapped(
            SongSummary,
            loadedResults: [SongSummary]
        )
    }

    @CasePathable
    enum Action: Equatable {
        case queryChanged(String)
        case submitButtonTapped
        case retryButtonTapped
        case cancel
        case resultTapped(MusicItemID)
        case pagination(SearchPaginationFeature.Action)
        case delegate(Delegate)
        case searchResponse(UUID, Result<SearchPage, MusicProviderError>)
    }

    enum CancelID { case search }

    @Dependency(\.providerSearch) var providerSearch
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .queryChanged(let query):
                state.query = query
                state.status = .idle
                return cancelSearchEffects()

            case .cancel:
                state.status = .idle
                return cancelSearchEffects()

            case .submitButtonTapped, .retryButtonTapped:
                guard state.providerAccess?.authorization == .authorized else {
                    return .none
                }
                let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    state.status = .idle
                    return cancelSearchEffects()
                }
                let requestID = uuid()
                state.status = .searching(requestID: requestID)
                return firstPageEffect(query: query, requestID: requestID)

            case .resultTapped(let songID):
                guard case .loaded(let pagination) = state.status,
                    let song = pagination.songs[id: songID]
                else { return .none }
                return .send(
                    .delegate(
                        .songTapped(
                            song,
                            loadedResults: Array(pagination.songs)
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
        .ifLet(\.pagination, action: \.pagination) {
            SearchPaginationFeature()
        }
    }

    private func firstPageEffect(
        query: String,
        requestID: UUID
    ) -> Effect<Action> {
        .run { send in
            do {
                let page = try await providerSearch.search(query, 20)
                await send(.searchResponse(requestID, .success(page)))
            } catch let error as MusicProviderError {
                await send(.searchResponse(requestID, .failure(error)))
            } catch {
                await send(.searchResponse(requestID, .failure(.network)))
            }
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }

    private func cancelSearchEffects() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.search),
            .cancel(id: SearchPaginationFeature.CancelID.nextPage)
        )
    }
}
