import ComposableArchitecture

/// Owns one accepted provider playback command.
@Reducer
struct PlaybackCommandFeature {
    @ObservableState
    struct State: Equatable {
        let command: Command
    }

    enum Command: Equatable {
        case play(MusicItemID)
        case resume(MusicItemID)
    }

    enum Delegate: Equatable {
        case succeeded(Command)
        case failed(Command, MusicProviderError)
    }

    enum Action: Equatable {
        case start
        case commandSucceeded
        case commandFailed(MusicProviderError)
        case delegate(Delegate)
    }

    @Dependency(\.musicProvider) var musicProvider

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                let command = state.command
                return .run { send in
                    do {
                        switch command {
                        case .play(let itemID):
                            try await musicProvider.play(itemID)
                        case .resume:
                            try await musicProvider.resume()
                        }
                        await send(.commandSucceeded)
                    } catch let error as MusicProviderError {
                        await send(.commandFailed(error))
                    } catch {
                        await send(.commandFailed(.playbackFailed))
                    }
                }

            case .commandSucceeded:
                return .send(.delegate(.succeeded(state.command)))

            case .commandFailed(let error):
                return .send(.delegate(.failed(state.command, error)))

            case .delegate:
                return .none
            }
        }
    }
}
