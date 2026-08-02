import ComposableArchitecture
import Foundation

/// Coordinates a submitted query across provider search children.
///
/// Each provider child owns its request lifecycle and first-page result. This
/// parent owns provider order, the frozen submitted query, destination
/// presentation, and delegation toward App. It does not perform provider
/// requests, paginate results, route tabs, or coordinate playback.
@Reducer
struct SearchReducer {
    @ObservableState
    struct State: Equatable {
        var query: String
        var submittedQuery: String?
        var providers: IdentifiedArrayOf<ProviderSearchReducer.State>
        @Presents var destination: ProviderSearchResultsReducer.State?

        init(query: String = "", providerIDs: [ProviderID]) {
            self.query = query
            submittedQuery = nil
            destination = nil

            var uniqueProviderIDs: [ProviderID] = []
            var seenProviderIDs: Set<ProviderID> = []
            for providerID in providerIDs {
                guard seenProviderIDs.insert(providerID).inserted else {
                    continue
                }
                uniqueProviderIDs.append(providerID)
            }

            if let libraryIndex = uniqueProviderIDs.firstIndex(of: .library) {
                uniqueProviderIDs.remove(at: libraryIndex)
                uniqueProviderIDs.insert(.library, at: 0)
            }

            providers = IdentifiedArray(
                uniqueElements: uniqueProviderIDs.map {
                    ProviderSearchReducer.State(
                        providerID: $0,
                        status: .inactive
                    )
                }
            )
        }
    }

    @CasePathable
    enum Action: Equatable {
        case queryChanged(String)
        case submitButtonTapped
        case searchSubmitted(String)
        case cancelProviderSearches
        case providers(IdentifiedActionOf<ProviderSearchReducer>)
        case destination(
            PresentationAction<ProviderSearchResultsReducer.Action>
        )
        case delegate(Delegate)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .queryChanged(let query):
                state.query = query
                return .send(.cancelProviderSearches)

            case .submitButtonTapped:
                let query = state.query.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !query.isEmpty else {
                    return .send(.cancelProviderSearches)
                }
                return .send(.searchSubmitted(query))

            case .searchSubmitted(let query):
                state.submittedQuery = query
                state.destination = nil
                let providerIDs = state.providers.prefix(5).map(\.id)
                return .merge(
                    providerIDs.map { providerID in
                        .send(
                            .providers(
                                .element(
                                    id: providerID,
                                    action: .searchRequested(query: query)
                                )
                            )
                        )
                    }
                )

            case .cancelProviderSearches:
                state.submittedQuery = nil
                state.destination = nil
                let providerIDs = state.providers.map(\.id)
                return .merge(
                    providerIDs.map { providerID in
                        .send(
                            .providers(
                                .element(
                                    id: providerID,
                                    action: .cancel
                                )
                            )
                        )
                    }
                )

            case .providers(
                .element(
                    id: let providerID,
                    action: .delegate(.activationRequested)
                )
            ):
                guard let query = state.submittedQuery else {
                    return .none
                }
                return .send(
                    .providers(
                        .element(
                            id: providerID,
                            action: .searchRequested(query: query)
                        )
                    )
                )

            case .providers(
                .element(
                    id: let providerID,
                    action: .delegate(.retryRequested)
                )
            ):
                guard let query = state.submittedQuery else {
                    return .none
                }
                return .send(
                    .providers(
                        .element(
                            id: providerID,
                            action: .searchRequested(query: query)
                        )
                    )
                )

            case .providers(
                .element(
                    id: let providerID,
                    action: .delegate(.seeAllRequested(let page))
                )
            ):
                guard let query = state.submittedQuery else {
                    return .none
                }
                state.destination = ProviderSearchResultsReducer.State(
                    providerID: providerID,
                    query: query,
                    tracks: page.tracks,
                    nextCursor: page.nextCursor,
                    status: .idle
                )
                return .none

            case .providers(
                .element(
                    id: _,
                    action: .delegate(.libraryRequested)
                )
            ):
                return .send(.delegate(.libraryRequested))

            case .providers(
                .element(
                    id: _,
                    action: .delegate(
                        .trackTapped(
                            let track,
                            loadedTracks: let loadedTracks
                        )
                    )
                )
            ):
                return .send(
                    .delegate(
                        .trackTapped(
                            track,
                            loadedTracks: loadedTracks
                        )
                    )
                )

            case .destination(
                .presented(
                    .delegate(
                        .trackTapped(
                            let track,
                            loadedTracks: let loadedTracks
                        )
                    )
                )
            ):
                return .send(
                    .delegate(
                        .trackTapped(
                            track,
                            loadedTracks: loadedTracks
                        )
                    )
                )

            case .providers, .destination, .delegate:
                return .none
            }
        }
        .forEach(\.providers, action: \.providers) {
            ProviderSearchReducer()
        }
        .ifLet(\.$destination, action: \.destination) {
            ProviderSearchResultsReducer()
        }
    }
}
