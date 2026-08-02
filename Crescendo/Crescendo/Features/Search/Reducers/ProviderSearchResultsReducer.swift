import ComposableArchitecture
import Foundation

/// Owns the accumulated results and continuation lifecycle for one provider.
///
/// The reducer freezes the submitted query with the provider identity, requests
/// subsequent pages, rejects stale responses, and delegates validated Track
/// selections with the complete loaded snapshot. Shared-query coordination,
/// provider activation, navigation, presentation, and playback remain outside
/// this boundary.
@Reducer
struct ProviderSearchResultsReducer {
    @ObservableState
    struct State: Equatable {
        let providerID: ProviderID
        let query: String
        var tracks: IdentifiedArrayOf<Track>
        var nextCursor: SearchCursor?
        var status: Status
    }

    @CasePathable
    enum Action: Equatable {
        case nextPageRequested
        case retryButtonTapped
        case resultTapped(TrackID)
        case cancel
        case continueSearch(SearchCursor, requestID: UUID)
        case searchPageResponse(
            UUID,
            Result<SearchPage, MusicProviderError>
        )
        case delegate(Delegate)
    }

    enum CancelID {
        case nextPage
    }

    @Dependency(\.providerSearchClients) var providerSearchClients
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .nextPageRequested:
                guard case .idle = state.status else { return .none }
                guard let cursor = state.nextCursor else { return .none }

                return .send(
                    .continueSearch(
                        cursor,
                        requestID: uuid()
                    )
                )

            case .retryButtonTapped:
                guard case .failed = state.status else { return .none }
                guard let cursor = state.nextCursor else { return .none }

                return .send(
                    .continueSearch(
                        cursor,
                        requestID: uuid()
                    )
                )

            case .resultTapped(let trackID):
                guard let track = state.tracks[id: trackID] else {
                    return .none
                }
                return .send(
                    .delegate(
                        .trackTapped(
                            track,
                            loadedTracks: state.tracks
                        )
                    )
                )

            case .continueSearch(let cursor, let requestID):
                state.status = .loading(requestID: requestID)
                let providerID = state.providerID
                return .run { send in
                    do {
                        guard
                            let searchClient = providerSearchClients[providerID]
                        else {
                            throw MusicProviderError.providerUnavailable(providerID)
                        }
                        let page = try await searchClient.searchPage(
                            .continuation(cursor),
                            20
                        )
                        await send(
                            .searchPageResponse(requestID, .success(page))
                        )
                    } catch let error as MusicProviderError {
                        await send(
                            .searchPageResponse(requestID, .failure(error))
                        )
                    } catch {
                        await send(
                            .searchPageResponse(requestID, .failure(.network))
                        )
                    }
                }
                .cancellable(id: CancelID.nextPage, cancelInFlight: true)

            case .cancel:
                state.status = .idle
                return .cancel(id: CancelID.nextPage)

            case .searchPageResponse(let requestID, .success(let page)):
                guard state.status == .loading(requestID: requestID) else {
                    return .none
                }

                for track in page.tracks where state.tracks[id: track.id] == nil {
                    state.tracks.append(track)
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

            case .delegate:
                return .none
            }
        }
    }
}
