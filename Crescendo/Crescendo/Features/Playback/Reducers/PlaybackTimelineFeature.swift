import ComposableArchitecture
import Foundation

/// Owns draft timeline positions and commits one seek when dragging ends.
@Reducer
struct PlaybackTimelineFeature {
    @ObservableState
    struct State: Equatable {
        var interaction: Interaction
    }

    enum Interaction: Equatable {
        case idle
        case dragging(position: TimeInterval)
        case seeking(requestID: UUID, position: TimeInterval)
    }

    enum Action: Equatable {
        case positionChanged(TimeInterval)
        case dragEnded
        case reset
        case seekSucceeded(requestID: UUID)
        case seekFailed(requestID: UUID, error: MusicProviderError)
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case transportFailed(MusicProviderError)
    }

    private enum CancelID {
        case seek
    }

    @Dependency(\.playbackControl) var playbackControl
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .positionChanged(let position):
                state.interaction = .dragging(position: position)
                return .cancel(id: CancelID.seek)

            case .dragEnded:
                guard case .dragging(let position) = state.interaction else {
                    return .none
                }
                let requestID = uuid()
                state.interaction = .seeking(
                    requestID: requestID,
                    position: position
                )
                return .run { send in
                    do {
                        try await playbackControl.seek(position)
                        await send(.seekSucceeded(requestID: requestID))
                    } catch let error as MusicProviderError {
                        await send(
                            .seekFailed(requestID: requestID, error: error)
                        )
                    } catch {
                        await send(
                            .seekFailed(
                                requestID: requestID,
                                error: .playbackFailed
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.seek, cancelInFlight: true)

            case .reset:
                state.interaction = .idle
                return .cancel(id: CancelID.seek)

            case .seekSucceeded(let requestID):
                guard
                    case .seeking(let activeRequestID, _) = state.interaction,
                    activeRequestID == requestID
                else {
                    return .none
                }
                state.interaction = .idle
                return .none

            case .seekFailed(let requestID, let error):
                guard
                    case .seeking(let activeRequestID, _) = state.interaction,
                    activeRequestID == requestID
                else {
                    return .none
                }
                state.interaction = .idle
                return .send(.delegate(.transportFailed(error)))

            case .delegate:
                return .none
            }
        }
    }
}
