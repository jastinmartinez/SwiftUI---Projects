import ComposableArchitecture

/// Owns one attempt to start playback for a provider-neutral music item.
@Reducer
struct MusicStartFeature {
    @ObservableState
    struct State: Equatable {
        let itemID: MusicItemID
    }

    enum Delegate: Equatable {
        case succeeded(MusicItemID)
        case failed(MusicItemID, MusicProviderError)
    }

    enum Action: Equatable {
        case start
        case playSucceeded
        case playFailed(MusicProviderError)
        case delegate(Delegate)
    }

    @Dependency(\.musicProvider) var musicProvider

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                let itemID = state.itemID
                return .run { send in
                    do {
                        try await musicProvider.play(itemID)
                        await send(.playSucceeded)
                    } catch let error as MusicProviderError {
                        await send(.playFailed(error))
                    } catch {
                        await send(.playFailed(.playbackFailed))
                    }
                }

            case .playSucceeded:
                return .send(.delegate(.succeeded(state.itemID)))

            case .playFailed(let error):
                return .send(.delegate(.failed(state.itemID, error)))

            case .delegate:
                return .none
            }
        }
    }
}
