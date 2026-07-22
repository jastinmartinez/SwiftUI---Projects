import ComposableArchitecture
import Foundation

/// Pauses an active provider before connecting a replacement provider.
@Reducer
struct ProviderSwitchFeature {
    enum Phase: Equatable {
        case ready(targetProviderID: ProviderID)
        case pausing(targetProviderID: ProviderID, requestID: UUID)
    }

    @ObservableState
    struct State: Equatable {
        let sourceProviderID: ProviderID
        var phase: Phase
    }

    enum Delegate: Equatable {
        case readyToConnect(ProviderID)
        case failed
        case cancelled
    }

    enum Action: Equatable {
        case start
        case targetChanged(ProviderID)
        case beginPause(targetProviderID: ProviderID, requestID: UUID)
        case cancel
        case pauseSucceeded(requestID: UUID)
        case pauseFailed(requestID: UUID)
        case delegate(Delegate)
    }

    private enum CancelID {
        case pause
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.playbackControl) var playbackControl

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                return .send(
                    .beginPause(
                        targetProviderID: state.phase.targetProviderID,
                        requestID: uuid()
                    )
                )

            case .targetChanged(let targetProviderID):
                guard state.phase.targetProviderID != targetProviderID else {
                    return .none
                }
                return .send(
                    .beginPause(
                        targetProviderID: targetProviderID,
                        requestID: uuid()
                    )
                )

            case .beginPause(let targetProviderID, let requestID):
                state.phase = .pausing(
                    targetProviderID: targetProviderID,
                    requestID: requestID
                )
                return .run { send in
                    do {
                        try await playbackControl.pause()
                        guard !Task.isCancelled else { return }
                        await send(.pauseSucceeded(requestID: requestID))
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(.pauseFailed(requestID: requestID))
                    }
                }
                .cancellable(id: CancelID.pause, cancelInFlight: true)

            case .cancel:
                return .concatenate(
                    .cancel(id: CancelID.pause),
                    .send(.delegate(.cancelled))
                )

            case .pauseSucceeded(let requestID):
                guard
                    case .pausing(let targetProviderID, requestID) = state.phase
                else {
                    return .none
                }
                return .send(.delegate(.readyToConnect(targetProviderID)))

            case .pauseFailed(let requestID):
                guard case .pausing(_, requestID) = state.phase else {
                    return .none
                }
                return .send(.delegate(.failed))

            case .delegate:
                return .none
            }
        }
    }
}

extension ProviderSwitchFeature.Phase {
    var targetProviderID: ProviderID {
        switch self {
        case .ready(let targetProviderID), .pausing(let targetProviderID, _):
            targetProviderID
        }
    }
}
