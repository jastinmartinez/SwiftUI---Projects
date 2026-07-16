import ComposableArchitecture
import Foundation

/// Owns persistent music selection, transport state, and provider-neutral commands.
@Reducer
struct MusicPlaybackFeature {
    @ObservableState
    struct State: Equatable {
        var selectedSong: SongSummary?
        var snapshot: MusicPlaybackSnapshot
        var playbackEligibility: CatalogPlaybackEligibility
        var capabilities: MusicProviderCapabilities

        var canPlaySelectedSong: Bool {
            selectedSong != nil
                && playbackEligibility == .eligible
                && capabilities.supportsEmbeddedPlayback
                && capabilities.supportsQueueReplacement
        }
    }

    enum Action: Equatable {
        case playTapped
        case pauseTapped
        case stopTapped
        case seekRequested(TimeInterval)
        case transportFinished
        case transportFailed(MusicProviderError)
        case snapshotReceived(MusicPlaybackSnapshot)
    }

    @Dependency(\.musicProvider) var musicProvider

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .playTapped:
                guard state.canPlaySelectedSong else { return .none }
                guard let itemID = state.selectedSong?.id else { return .none }
                state.snapshot.status = .loading
                return transportEffect {
                    try await musicProvider.play(itemID)
                }

            case .pauseTapped:
                return transportEffect {
                    try await musicProvider.pause()
                }

            case .stopTapped:
                return transportEffect {
                    try await musicProvider.stop()
                }

            case .seekRequested(let time):
                guard state.capabilities.supportsSeeking else { return .none }
                return transportEffect {
                    try await musicProvider.seek(time)
                }

            case .transportFinished:
                return .none

            case .transportFailed(let error):
                state.snapshot.status = .failed
                state.snapshot.error = error
                return .none

            case .snapshotReceived(let snapshot):
                state.snapshot = snapshot
                return .none
            }
        }
    }

    /// Converts one provider command into normalized reducer completion or failure actions.
    private func transportEffect(
        _ operation: @escaping @Sendable () async throws -> Void
    ) -> Effect<Action> {
        .run { send in
            do {
                try await operation()
                await send(.transportFinished)
            } catch let error as MusicProviderError {
                await send(.transportFailed(error))
            } catch {
                await send(.transportFailed(.playbackFailed))
            }
        }
    }
}
