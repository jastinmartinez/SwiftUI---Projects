import ComposableArchitecture
import Foundation

/// Owns continuation-page state and operations for loaded search results.
@Reducer
struct SearchPaginationFeature {
    @ObservableState
    struct State: Equatable {
        var songs: IdentifiedArrayOf<SongSummary>
        var nextCursor: SearchCursor?
        var status: Status
    }

    enum Status: Equatable {
        case idle
        case loading(requestID: UUID)
        case failed(MusicProviderError)
    }

    enum Action: Equatable {
        case nextPageRequested
        case retryButtonTapped
        case cancel
        case searchPageResponse(
            UUID,
            Result<SearchPage, MusicProviderError>
        )
    }

    enum CancelID {
        case nextPage
    }

    @Dependency(\.providerSearch) var providerSearch
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .nextPageRequested:
                guard case .idle = state.status else { return .none }
                guard let cursor = state.nextCursor else { return .none }

                let requestID = uuid()
                state.status = .loading(requestID: requestID)
                return nextPageEffect(
                    cursor: cursor,
                    requestID: requestID
                )

            case .retryButtonTapped:
                guard case .failed = state.status else { return .none }
                guard let cursor = state.nextCursor else { return .none }

                let requestID = uuid()
                state.status = .loading(requestID: requestID)
                return nextPageEffect(
                    cursor: cursor,
                    requestID: requestID
                )

            case .cancel:
                state.status = .idle
                return .cancel(id: CancelID.nextPage)

            case .searchPageResponse(let requestID, .success(let page)):
                guard state.status == .loading(requestID: requestID) else {
                    return .none
                }

                for song in page.songs where state.songs[id: song.id] == nil {
                    state.songs.append(song)
                }
                state.nextCursor = page.nextCursor
                state.status = .idle
                return .none

            case .searchPageResponse(let requestID, .failure(let error)):
                guard state.status == .loading(requestID: requestID) else {
                    return .none
                }

                state.status = .failed(error)
                return .none
            }
        }
    }

    private func nextPageEffect(
        cursor: SearchCursor,
        requestID: UUID
    ) -> Effect<Action> {
        .run { send in
            do {
                let page = try await providerSearch.nextSearchPage(cursor, 20)
                await send(.searchPageResponse(requestID, .success(page)))
            } catch let error as MusicProviderError {
                await send(.searchPageResponse(requestID, .failure(error)))
            } catch {
                await send(.searchPageResponse(requestID, .failure(.network)))
            }
        }
        .cancellable(id: CancelID.nextPage, cancelInFlight: true)
    }
}
