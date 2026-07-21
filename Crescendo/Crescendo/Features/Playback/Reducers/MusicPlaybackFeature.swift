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
        var timeline: MusicPlaybackTimelineFeature.State

        var canPlaySelectedSong: Bool {
            guard let itemID = selectedSong?.id,
                playbackEligibility == .eligible,
                capabilities.supportsEmbeddedPlayback
            else {
                return false
            }
            let shouldResume =
                phase.snapshot.currentItem?.id == itemID
                && phase.snapshot.status == .paused
            return shouldResume || capabilities.supportsQueueReplacement
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
        case songTapped(
            SongSummary,
            playbackEligibility: CatalogPlaybackEligibility
        )
        case applySongTap(
            SongSummary,
            playbackEligibility: CatalogPlaybackEligibility
        )
        case playTapped
        case requestPlayback
        case playbackCommandAccepted
        case delegate(Delegate)
        case pauseTapped
        case stopTapped
        case timeline(MusicPlaybackTimelineFeature.Action)
        case transportFinished
        case transportFailed(MusicProviderError)
        case snapshotReceived(MusicPlaybackSnapshot)
    }

    enum CancelID {
        case playbackObservation
    }

    @Dependency(\.playbackControl) var playbackControl
    @Dependency(\.playbackObservation) var playbackObservation

    var body: some ReducerOf<Self> {
        Scope(state: \.timeline, action: \.timeline) {
            MusicPlaybackTimelineFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    let snapshots = await playbackObservation.playbackSnapshots()
                    for await snapshot in snapshots {
                        await send(.snapshotReceived(snapshot))
                    }
                }
                .cancellable(
                    id: CancelID.playbackObservation,
                    cancelInFlight: true
                )

            case .songTapped(let song, let playbackEligibility):
                let isDifferentSong = state.selectedSong?.id != song.id
                if isDifferentSong {
                    return .concatenate(
                        .send(.timeline(.reset)),
                        .send(
                            .applySongTap(
                                song,
                                playbackEligibility: playbackEligibility
                            )
                        )
                    )
                }
                return .send(
                    .applySongTap(
                        song,
                        playbackEligibility: playbackEligibility
                    )
                )

            case .applySongTap(let song, let playbackEligibility):
                state.selectedSong = song
                state.playbackEligibility = playbackEligibility
                return .send(.requestPlayback)

            case .playTapped:
                return .send(.requestPlayback)

            case .requestPlayback:
                guard let itemID = state.selectedSong?.id,
                    state.playbackEligibility == .eligible,
                    state.capabilities.supportsEmbeddedPlayback
                else { return .none }
                let snapshot = state.phase.snapshot
                let isCurrentItem = snapshot.currentItem?.id == itemID
                if isCurrentItem, snapshot.status == .playing {
                    return .none
                }
                if isCurrentItem, snapshot.status == .paused {
                    return .send(.delegate(.resumeRequested(itemID)))
                }
                guard state.capabilities.supportsQueueReplacement else {
                    return .none
                }
                return .send(.delegate(.playRequested(itemID)))

            case .playbackCommandAccepted:
                state.phase = .loading(state.phase.snapshot)
                return .none

            case .delegate:
                return .none

            case .pauseTapped:
                state.phase = .observing(state.phase.snapshot)
                return transportEffect {
                    try await playbackControl.pause()
                }

            case .stopTapped:
                state.phase = .observing(state.phase.snapshot)
                return .concatenate(
                    .send(.timeline(.reset)),
                    transportEffect {
                        try await playbackControl.stop()
                    }
                )

            case .timeline(.delegate(.transportFailed(let error))):
                state.phase = .failed(
                    error,
                    lastSnapshot: state.phase.snapshot
                )
                return .none

            case .timeline:
                return .none

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
