import ComposableArchitecture

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action: Equatable {
        case task
    }

    var body: some ReducerOf<Self> {
        Reduce { _, action in
            switch action {
            case .task:
                return .none
            }
        }
    }
}
