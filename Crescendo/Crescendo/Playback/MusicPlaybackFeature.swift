import ComposableArchitecture
import Foundation

/// Owns persistent music selection, playback state, and provider-neutral commands.
@Reducer
struct MusicPlaybackFeature {
    @ObservableState
    struct State: Equatable {
        var selectedSong: SongSummary?
        var phase: Phase
        var playbackEligibility: CatalogPlaybackEligibility
        var capabilities: MusicProviderCapabilities

        var canPlaySelectedSong: Bool {
            selectedSong != nil
                && playbackEligibility == .eligible
                && capabilities.supportsEmbeddedPlayback
                && capabilities.supportsQueueReplacement
        }
    }

    enum Phase: Equatable {
        /// Accepts provider observations as the current playback snapshot.
        case observing(MusicPlaybackSnapshot)
        /// Retains the latest observation while a Play command is in flight.
        case loading(MusicPlaybackSnapshot)
        /// Retains both the command failure and the latest provider observation.
        case failed(
            MusicProviderError,
            lastSnapshot: MusicPlaybackSnapshot
        )

        /// Returns the most recent provider observation without discarding the active case.
        var snapshot: MusicPlaybackSnapshot {
            switch self {
            case .observing(let snapshot), .loading(let snapshot):
                snapshot
            case .failed(_, let lastSnapshot):
                lastSnapshot
            }
        }
    }

    /// Events emitted after validating child-owned playback intent.
    enum Delegate: Equatable {
        case playRequested(MusicItemID)
        case resumeRequested(MusicItemID)
    }

    enum Action: Equatable {
        case task
        case playTapped
        case playbackCommandAccepted
        case delegate(Delegate)
        case pauseTapped
        case stopTapped
        case seekRequested(TimeInterval)
        case transportFinished
        case transportFailed(MusicProviderError)
        case snapshotReceived(MusicPlaybackSnapshot)
    }

    enum CancelID {
        case playbackObservation
    }

    @Dependency(\.musicProvider) var musicProvider

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    let snapshots = await musicProvider.playbackSnapshots()
                    for await snapshot in snapshots {
                        await send(.snapshotReceived(snapshot))
                    }
                }
                .cancellable(
                    id: CancelID.playbackObservation,
                    cancelInFlight: true
                )

            case .playTapped:
                guard state.canPlaySelectedSong,
                    let itemID = state.selectedSong?.id
                else { return .none }
                let shouldResume =
                    state.phase.snapshot.currentItem?.id == itemID
                    && state.phase.snapshot.status == .paused
                return .send(
                    .delegate(
                        shouldResume
                            ? .resumeRequested(itemID)
                            : .playRequested(itemID)
                    )
                )

            case .playbackCommandAccepted:
                state.phase = .loading(state.phase.snapshot)
                return .none

            case .delegate:
                return .none

            case .pauseTapped:
                state.phase = .observing(state.phase.snapshot)
                return transportEffect {
                    try await musicProvider.pause()
                }

            case .stopTapped:
                state.phase = .observing(state.phase.snapshot)
                return transportEffect {
                    try await musicProvider.stop()
                }

            case .seekRequested(let time):
                guard state.capabilities.supportsSeeking else { return .none }
                state.phase = .observing(state.phase.snapshot)
                return transportEffect {
                    try await musicProvider.seek(time)
                }

            case .transportFinished:
                guard case .loading(let snapshot) = state.phase else {
                    return .none
                }
                state.phase = .observing(snapshot)
                return .none

            case .transportFailed(let error):
                state.phase = .failed(
                    error,
                    lastSnapshot: state.phase.snapshot
                )
                return .none

            case .snapshotReceived(let snapshot):
                switch state.phase {
                case .observing:
                    state.phase = .observing(snapshot)
                case .loading:
                    state.phase = .loading(snapshot)
                case .failed(let error, _):
                    state.phase = .failed(
                        error,
                        lastSnapshot: snapshot
                    )
                }
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
