import ComposableArchitecture
import Foundation

/// Owns the first-page search lifecycle and interactions for one provider rail.
///
/// The reducer routes initial search through its provider identity, stores one
/// immutable first page, rejects stale responses, and validates result actions
/// before delegating facts to its parent. The parent remains responsible for
/// starting every configured provider, the latest submitted query, and
/// destination navigation.
@Reducer
struct ProviderSearchReducer {
    @ObservableState
    struct State: Equatable, Identifiable {
        let providerID: ProviderID
        var status: Status

        var id: ProviderID { providerID }
    }

    @CasePathable
    enum Action: Equatable {
        case searchRequested(query: String)
        case cancel
        case seeAllButtonTapped
        case resultTapped(TrackID)
        case searchResponse(
            UUID,
            Result<SearchPage, MusicProviderError>
        )
        case delegate(Delegate)
    }

    private enum CancelID: Hashable {
        case search(ProviderID)
    }

    @Dependency(\.providerSearchClients) var providerSearchClients
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .searchRequested(let query):
                let requestID = uuid()
                let providerID = state.providerID
                state.status = .searching(requestID: requestID)

                return .run { send in
                    do {
                        guard
                            let searchClient = providerSearchClients[providerID]
                        else {
                            throw MusicProviderError.providerUnavailable(providerID)
                        }
                        let page = try await searchClient.searchPage(
                            .initial(query: query),
                            20
                        )
                        await send(
                            .searchResponse(requestID, .success(page))
                        )
                    } catch let error as MusicProviderError {
                        await send(
                            .searchResponse(requestID, .failure(error))
                        )
                    } catch {
                        await send(
                            .searchResponse(requestID, .failure(.network))
                        )
                    }
                }
                .cancellable(
                    id: CancelID.search(providerID),
                    cancelInFlight: true
                )

            case .cancel:
                state.status = .inactive
                return .cancel(
                    id: CancelID.search(state.providerID)
                )

            case .seeAllButtonTapped:
                guard case .loaded(let page) = state.status else {
                    return .none
                }
                guard !page.tracks.isEmpty else { return .none }
                return .send(.delegate(.seeAllRequested(page)))

            case .resultTapped(let trackID):
                guard case .loaded(let page) = state.status else {
                    return .none
                }
                guard let track = page.tracks[id: trackID] else {
                    return .none
                }
                return .send(
                    .delegate(
                        .trackTapped(
                            track,
                            loadedTracks: page.tracks
                        )
                    )
                )

            case .searchResponse(let requestID, .success(let searchPage)):
                guard state.status == .searching(requestID: requestID) else {
                    return .none
                }
                state.status = .loaded(
                    Page(
                        tracks: IdentifiedArray(
                            uniqueElements: searchPage.tracks
                        ),
                        nextCursor: searchPage.nextCursor
                    )
                )
                return .none

            case .searchResponse(let requestID, .failure(let error)):
                guard state.status == .searching(requestID: requestID) else {
                    return .none
                }
                state.status = .failed(error)
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
