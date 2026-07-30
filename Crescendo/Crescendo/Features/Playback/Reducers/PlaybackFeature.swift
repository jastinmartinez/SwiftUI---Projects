import ComposableArchitecture
import Foundation

/// Coordinates playback observation and the Queue, Timeline, Session, and
/// Transition domains.
@Reducer
struct PlaybackFeature {
    @ObservableState
    struct State: Equatable {
        var queue: PlaybackQueueFeature.State
        var timeline: PlaybackTimelineFeature.State
        var session: PlaybackSessionFeature.State
        var transition: PlaybackTransitionFeature.State?
        var failureNotice: PlaybackFailureNotice?
        var isPlayerPresented: Bool
    }

    enum Action: Equatable {
        case task
        case selectionReceived(
            TrackID,
            loadedResults: IdentifiedArrayOf<Track>
        )
        case playPauseTapped
        case stopTapped
        case previousTapped
        case nextTapped
        case repeatTapped
        case shuffleTapped
        case timelinePositionChanged(TimeInterval)
        case timelineInteractionEnded
        case restartTapped
        case seekBackwardTapped
        case seekForwardTapped
        case setPlayerPresented(Bool)
        case observationReceived(PlaybackObservation)
        case confirmedSnapshotReceived(PlaybackSnapshot)
        case queue(PlaybackQueueFeature.Action)
        case timeline(PlaybackTimelineFeature.Action)
        case session(PlaybackSessionFeature.Action)
        case transition(PlaybackTransitionFeature.Action)
    }

    private enum CancelID {
        case playbackObservation
    }

    @Dependency(\.playbackObservation) var playbackObservation

    var body: some ReducerOf<Self> {
        Scope(state: \.queue, action: \.queue) {
            PlaybackQueueFeature()
        }
        Scope(state: \.timeline, action: \.timeline) {
            PlaybackTimelineFeature()
        }
        Scope(state: \.session, action: \.session) {
            PlaybackSessionFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                return .run { send in
                    let observations =
                        await playbackObservation.observations()
                    for await observation in observations {
                        await send(.observationReceived(observation))
                    }
                }
                .cancellable(
                    id: CancelID.playbackObservation,
                    cancelInFlight: true
                )

            case .selectionReceived(let trackID, let loadedResults):
                return .send(
                    .queue(
                        .selectionRequested(
                            trackID,
                            loadedResults: loadedResults
                        )
                    )
                )

            case .playPauseTapped:
                guard state.canRequestPlayPause else { return .none }
                state.failureNotice = nil
                return .send(.session(.playPauseRequested))

            case .stopTapped:
                guard state.canRequestStop else { return .none }
                state.failureNotice = nil
                if state.transition != nil {
                    return .send(.transition(.stopRequested))
                }
                return .send(.session(.stopRequested))

            case .previousTapped:
                guard state.canRequestPrevious else { return .none }
                state.failureNotice = nil
                return .send(.queue(.previousTapped))

            case .nextTapped:
                guard state.canRequestNext else { return .none }
                state.failureNotice = nil
                return .send(.queue(.nextTapped))

            case .repeatTapped:
                guard state.canRequestRepeat else { return .none }
                state.failureNotice = nil
                return .send(.queue(.repeatTapped))

            case .shuffleTapped:
                guard state.canRequestShuffle else { return .none }
                state.failureNotice = nil
                return .send(.queue(.shuffleTapped))

            case .timelinePositionChanged(let requestedPosition):
                guard state.canRequestSeek,
                    let duration = state.timelineDuration
                else {
                    return .none
                }
                let position = min(max(requestedPosition, 0), duration)
                return .send(.timeline(.positionChanged(position)))

            case .timelineInteractionEnded:
                guard state.canRequestSeek,
                    let duration = state.timelineDuration
                else {
                    return .none
                }
                let position = min(
                    max(state.timeline.position, 0),
                    duration
                )
                guard position != state.timeline.position else {
                    return .send(.timeline(.dragEnded))
                }
                return .concatenate(
                    .send(.timeline(.positionChanged(position))),
                    .send(.timeline(.dragEnded))
                )

            case .restartTapped:
                guard state.canRequestSeek else { return .none }
                return .send(.timeline(.seekRequested(0)))

            case .seekBackwardTapped:
                guard state.canRequestSeek,
                    let duration = state.timelineDuration
                else {
                    return .none
                }
                let target = min(
                    max(state.timeline.position - 15, 0),
                    duration
                )
                return .send(.timeline(.seekRequested(target)))

            case .seekForwardTapped:
                guard state.canRequestSeek,
                    let duration = state.timelineDuration
                else {
                    return .none
                }
                let target = min(
                    state.timeline.position + 15,
                    duration
                )
                return .send(.timeline(.seekRequested(target)))

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none

            case .observationReceived(.snapshot(let snapshot)):
                if state.transition != nil {
                    return .send(
                        .transition(.snapshotReceived(snapshot))
                    )
                }
                return .send(.confirmedSnapshotReceived(snapshot))

            case .observationReceived(.completed(let trackID)):
                guard state.transition == nil,
                    trackID == state.queue.current?.currentTrackID
                else {
                    return .none
                }
                return .send(.queue(.currentTrackCompleted(trackID)))

            case .observationReceived(.failed(let trackID, let failure)):
                if state.transition != nil {
                    return .send(
                        .transition(
                            .runtimeFailureReceived(trackID, failure)
                        )
                    )
                }
                guard
                    trackID == nil
                        || trackID
                            == state.queue.current?.currentTrackID,
                    let noticeTrackID =
                        trackID
                        ?? state.queue.current?.currentTrackID
                else {
                    return .none
                }
                state.failureNotice = PlaybackFailureNotice(
                    trackID: noticeTrackID,
                    failure: failure
                )
                return .none

            case .confirmedSnapshotReceived(let snapshot):
                if state.failureNotice?.trackID == snapshot.currentTrackID {
                    state.failureNotice = nil
                }
                let timelineEffect: Effect<Action> = .send(
                    .timeline(
                        .confirmedSnapshot(
                            position: snapshot.position,
                            duration: snapshot.duration,
                            isSeekable: snapshot.isSeekable
                        )
                    )
                )
                let sessionEffect: Effect<Action> = .send(
                    .session(
                        .confirmedSnapshot(
                            status: snapshot.status,
                            position: snapshot.position
                        )
                    )
                )
                guard let currentTrackID = snapshot.currentTrackID else {
                    return .concatenate(
                        timelineEffect,
                        sessionEffect
                    )
                }
                return .concatenate(
                    .send(
                        .queue(
                            .currentTrackConfirmed(currentTrackID)
                        )
                    ),
                    timelineEffect,
                    sessionEffect
                )

            case .queue(
                .delegate(.transitionRequested(let trackID))
            ):
                guard state.queue.pendingTrack?.id == trackID else {
                    return .none
                }
                let intent = PlaybackTransitionFeature.Intent(
                    targetTrackID: trackID,
                    baselineTrackID:
                        state.queue.current?.currentTrackID
                )
                let transitionEffect: Effect<Action>
                if state.transition == nil {
                    state.transition = PlaybackTransitionFeature.State(
                        phase: .starting(intent)
                    )
                    transitionEffect = .send(.transition(.start))
                } else {
                    transitionEffect = .send(
                        .transition(.supersede(intent))
                    )
                }
                state.failureNotice = nil
                if state.queue.current == nil {
                    state.isPlayerPresented = true
                }
                return .concatenate(
                    .send(.session(.cancelPendingStatusChange)),
                    transitionEffect
                )

            case .transition(.cancel),
                .transition(.stopRequested):
                return .send(.queue(.pendingFollowUpDiscarded))

            case .transition(
                .delegate(.confirmedSnapshotReady(let snapshot))
            ):
                return .send(.confirmedSnapshotReceived(snapshot))

            case .transition(
                .delegate(
                    .confirmedPlaybackFailed(
                        let trackID,
                        let failure
                    )
                )
            ):
                guard
                    let noticeTrackID =
                        trackID
                        ?? state.queue.current?.currentTrackID
                else {
                    return .none
                }
                state.failureNotice = PlaybackFailureNotice(
                    trackID: noticeTrackID,
                    failure: failure
                )
                return .none

            case .transition(
                .delegate(.confirmationReady(let confirmation))
            ):
                let snapshot = confirmation.snapshot
                return .concatenate(
                    .send(
                        .queue(
                            .pendingChangeConfirmed(
                                confirmation.intent.targetTrackID
                            )
                        )
                    ),
                    .send(
                        .timeline(
                            .confirmedSnapshot(
                                position: snapshot.position,
                                duration: snapshot.duration,
                                isSeekable: snapshot.isSeekable
                            )
                        )
                    ),
                    .send(
                        .session(
                            .confirmedSnapshot(
                                status: snapshot.status,
                                position: snapshot.position
                            )
                        )
                    ),
                    .send(.transition(.confirmationApplied))
                )

            case .transition(
                .delegate(.completed(let completion))
            ):
                switch completion {
                case .confirmed:
                    state.transition = nil
                    return .none

                case .cancelled:
                    state.transition = nil
                    return .send(.queue(.pendingChangesDiscarded))

                case .failed(let trackID, let failure):
                    state.transition = nil
                    state.failureNotice = PlaybackFailureNotice(
                        trackID: trackID,
                        failure: failure
                    )
                    return .send(.queue(.pendingChangesDiscarded))

                case .stopReady:
                    state.transition = nil
                    return .concatenate(
                        .send(.queue(.pendingChangesDiscarded)),
                        .send(.session(.stopRequested))
                    )
                }

            case .session(.delegate(.statusConfirmed)):
                state.failureNotice = nil
                return .none

            case .session(.delegate(.stopCompleted)):
                state.failureNotice = nil
                return .send(.timeline(.resetPosition))

            case .session(
                .delegate(.transportFailed(let failure))
            ),
                .timeline(
                    .delegate(.transportFailed(let failure))
                ):
                guard
                    let trackID =
                        state.queue.current?.currentTrackID
                else {
                    return .none
                }
                state.failureNotice = PlaybackFailureNotice(
                    trackID: trackID,
                    failure: failure
                )
                return .none

            case .queue, .timeline, .session, .transition:
                return .none
            }
        }
        .ifLet(\.transition, action: \.transition) {
            PlaybackTransitionFeature()
        }
    }
}

extension PlaybackFeature.State {
    var commandPolicy: PlaybackCommandPolicy {
        PlaybackCommandPolicy(
            queue: queue,
            timeline: timeline,
            session: session,
            transition: transition
        )
    }

    var canRequestPlayPause: Bool { commandPolicy.allows(.playPause) }
    var canRequestStop: Bool { commandPolicy.allows(.stop) }
    var canRequestSeek: Bool { commandPolicy.allows(.seek) }
    var canRequestPrevious: Bool { commandPolicy.allows(.previous) }
    var canRequestNext: Bool { commandPolicy.allows(.next) }
    var canRequestRepeat: Bool { commandPolicy.allows(.repeatMode) }
    var canRequestShuffle: Bool { commandPolicy.allows(.shuffleMode) }

    /// The player-confirmed timeline duration controls seek commands and clamping.
    var timelineDuration: TimeInterval? {
        timeline.duration
    }
}
