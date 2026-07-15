import ComposableArchitecture

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        let registeredProviders: [MusicProviderDescriptor]
        var activeProviderID: MusicProviderID?

        var requiresProviderSelection: Bool {
            registeredProviders.count > 1 && activeProviderID == nil
        }

        init(
            registeredProviders: [MusicProviderDescriptor],
            activeProviderID: MusicProviderID?
        ) {
            self.registeredProviders = registeredProviders
            self.activeProviderID = activeProviderID
        }
    }

    enum Action: Equatable {
        case task
        case providerSelected(MusicProviderID)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                if state.activeProviderID == nil, state.registeredProviders.count == 1 {
                    state.activeProviderID = state.registeredProviders[0].id
                }
                return .none

            case .providerSelected(let providerID):
                guard
                    state.registeredProviders.contains(
                        where: { $0.id == providerID }
                    )
                else {
                    return .none
                }
                state.activeProviderID = providerID
                return .none
            }
        }
    }
}
