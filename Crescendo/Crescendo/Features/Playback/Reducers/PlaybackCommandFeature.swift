import ComposableArchitecture
import Foundation

/// Owns one accepted provider playback command.
@Reducer
struct PlaybackCommandFeature {
    @ObservableState
    struct State: Equatable {
        var command: Command
        var requestID: UUID
    }

    enum Command: Equatable {
        case play(MusicItemID)
        case resume(MusicItemID)
    }

    enum Delegate: Equatable {
        case completed(
            requestID: UUID,
            result: Result<Command, MusicProviderError>
        )
    }

    enum Action: Equatable {
        case start
        case replace(Command, requestID: UUID)
        case execute(Command, requestID: UUID)
        case response(
            requestID: UUID,
            result: Result<Command, MusicProviderError>
        )
        case delegate(Delegate)
    }

    private enum CancelID {
        case command
    }

    @Dependency(\.musicProvider) var musicProvider

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .send(
                    .execute(state.command, requestID: state.requestID)
                )

            case .replace(let command, let requestID):
                return .send(.execute(command, requestID: requestID))

            case .execute(let command, let requestID):
                state.command = command
                state.requestID = requestID
                return .run { send in
                    do {
                        switch command {
                        case .play(let itemID):
                            try await musicProvider.play(itemID)
                        case .resume:
                            try await musicProvider.resume()
                        }
                        try Task.checkCancellation()
                        await send(
                            .response(
                                requestID: requestID,
                                result: .success(command)
                            )
                        )
                    } catch is CancellationError {
                        return
                    } catch let error as MusicProviderError {
                        guard !Task.isCancelled else { return }
                        await send(
                            .response(
                                requestID: requestID,
                                result: .failure(error)
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .response(
                                requestID: requestID,
                                result: .failure(.playbackFailed)
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.command, cancelInFlight: true)

            case .response(let requestID, let result):
                guard requestID == state.requestID else {
                    return .none
                }
                return .send(
                    .delegate(.completed(requestID: requestID, result: result))
                )

            case .delegate:
                return .none
            }
        }
    }
}
