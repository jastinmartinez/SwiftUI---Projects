import ComposableArchitecture

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        let registeredProviders: [MusicProviderDescriptor]
        var activeProviderID: MusicProviderID?
        var search: SearchFeature.State

        var requiresProviderSelection: Bool {
            registeredProviders.count > 1 && activeProviderID == nil
        }

        init(
            registeredProviders: [MusicProviderDescriptor],
            activeProviderID: MusicProviderID?,
            search: SearchFeature.State
        ) {
            self.registeredProviders = registeredProviders
            self.activeProviderID = activeProviderID
            self.search = search
        }
    }

    enum Action: Equatable {
        case task
        case providerSelected(MusicProviderID)
        case search(SearchFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                if state.activeProviderID == nil, state.registeredProviders.count == 1 {
                    state.activeProviderID = state.registeredProviders[0].id
                }
                return .none

            case .providerSelected(let providerID):
                let isRegisteredProvider = state.registeredProviders.contains(
                    where: { $0.id == providerID }
                )
                guard isRegisteredProvider else {
                    return .none
                }
                state.activeProviderID = providerID
                return .none

            case .search:
                return .none
            }
        }
    }
}
