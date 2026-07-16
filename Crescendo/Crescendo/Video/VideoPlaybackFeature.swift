import ComposableArchitecture
import Foundation

/// Owns video URL input, load progress, failures, and playback observation.
@Reducer
struct VideoPlaybackFeature {
    @ObservableState
    struct State: Equatable {
        var urlText: String
        var loadedVideoURL: URL?
        var phase: Phase
        var observationID: UUID?

        var isLoading: Bool {
            guard case .loading = phase else { return false }
            return true
        }
    }

    enum Phase: Equatable, Sendable {
        /// Accepts controller observations as the current playback snapshot.
        case observing(VideoPlaybackSnapshot)
        /// Retains the latest observation while a URL load is in flight.
        case loading(
            requestID: UUID,
            lastSnapshot: VideoPlaybackSnapshot
        )
        /// Retains both the load failure and the latest controller observation.
        case failed(
            VideoPlaybackError,
            lastSnapshot: VideoPlaybackSnapshot
        )

        /// Returns the latest valid controller observation in every phase.
        var snapshot: VideoPlaybackSnapshot {
            switch self {
            case .observing(let snapshot):
                snapshot
            case .loading(_, let lastSnapshot), .failed(_, let lastSnapshot):
                lastSnapshot
            }
        }

        /// Returns the preserved snapshot only for the active load request.
        func lastSnapshot(
            forLoadingRequest requestID: UUID
        ) -> VideoPlaybackSnapshot? {
            switch self {
            case .loading(let activeRequestID, let lastSnapshot):
                guard activeRequestID == requestID else { return nil }
                return lastSnapshot
            case .observing, .failed:
                return nil
            }
        }
    }

    enum Action: Equatable {
        case task
        case urlChanged(String)
        case loadSubmitted
        case retryTapped
        case loadSucceeded(
            requestID: UUID,
            url: URL
        )
        case loadFailed(
            requestID: UUID,
            error: VideoPlaybackError
        )
        case snapshotReceived(
            observationID: UUID,
            snapshot: VideoPlaybackSnapshot
        )
        case seekRequested(TimeInterval)
        case routeExited
    }

    enum CancelID {
        case load
        case observation
    }

    @Dependency(\.videoPlayback) var videoPlayback
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                let observationID = uuid()
                state.observationID = observationID
                return .run { send in
                    let snapshots = await videoPlayback.playbackSnapshots()
                    for await snapshot in snapshots {
                        await send(
                            .snapshotReceived(
                                observationID: observationID,
                                snapshot: snapshot
                            )
                        )
                    }
                }
                .cancellable(
                    id: CancelID.observation,
                    cancelInFlight: true
                )

            case .urlChanged(let urlText):
                state.urlText = urlText
                if case .failed(_, let lastSnapshot) = state.phase {
                    state.phase = .observing(lastSnapshot)
                }
                return .none

            case .loadSubmitted, .retryTapped:
                guard !state.isLoading else { return .none }
                let submittedURLText = state.urlText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !submittedURLText.isEmpty else {
                    state.phase = .failed(
                        .emptyURL,
                        lastSnapshot: state.phase.snapshot
                    )
                    return .none
                }
                guard let url = URL(string: submittedURLText),
                    let scheme = url.scheme
                else {
                    state.phase = .failed(
                        .invalidURL,
                        lastSnapshot: state.phase.snapshot
                    )
                    return .none
                }
                guard scheme.lowercased() == "https" else {
                    state.phase = .failed(
                        .unsupportedScheme,
                        lastSnapshot: state.phase.snapshot
                    )
                    return .none
                }
                guard url.host != nil else {
                    state.phase = .failed(
                        .invalidURL,
                        lastSnapshot: state.phase.snapshot
                    )
                    return .none
                }
                let hasCredentials = url.user != nil || url.password != nil
                guard !hasCredentials else {
                    state.phase = .failed(
                        .invalidURL,
                        lastSnapshot: state.phase.snapshot
                    )
                    return .none
                }
                let requestID = uuid()
                state.phase = .loading(
                    requestID: requestID,
                    lastSnapshot: state.phase.snapshot
                )
                return loadEffect(url: url, requestID: requestID)

            case .loadSucceeded(let requestID, let url):
                let lastSnapshot = state.phase.lastSnapshot(
                    forLoadingRequest: requestID
                )
                guard let lastSnapshot else { return .none }
                state.loadedVideoURL = url
                state.phase = .observing(lastSnapshot)
                return .none

            case .loadFailed(let requestID, let error):
                let lastSnapshot = state.phase.lastSnapshot(
                    forLoadingRequest: requestID
                )
                guard let lastSnapshot else { return .none }
                state.phase = .failed(
                    error,
                    lastSnapshot: lastSnapshot
                )
                return .none

            case .snapshotReceived(let observationID, let snapshot):
                guard state.observationID == observationID else {
                    return .none
                }
                switch state.phase {
                case .observing:
                    state.phase = .observing(snapshot)
                case .loading(let requestID, _):
                    state.phase = .loading(
                        requestID: requestID,
                        lastSnapshot: snapshot
                    )
                case .failed(let error, _):
                    state.phase = .failed(
                        error,
                        lastSnapshot: snapshot
                    )
                }
                return .none

            case .seekRequested(let time):
                return .run { _ in
                    await videoPlayback.seek(time)
                }

            case .routeExited:
                if case .loading(_, let lastSnapshot) = state.phase {
                    state.phase = .observing(lastSnapshot)
                }
                state.observationID = nil
                return .merge(
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.observation)
                )
            }
        }
    }

    /// Loads one validated URL and converts completion into feature actions.
    private func loadEffect(
        url: URL,
        requestID: UUID
    ) -> Effect<Action> {
        .run { send in
            do {
                try await videoPlayback.load(url)
                await send(
                    .loadSucceeded(
                        requestID: requestID,
                        url: url
                    )
                )
            } catch let error as VideoPlaybackError {
                await send(
                    .loadFailed(
                        requestID: requestID,
                        error: error
                    )
                )
            } catch {
                await send(
                    .loadFailed(
                        requestID: requestID,
                        error: .loadFailed
                    )
                )
            }
        }
        .cancellable(
            id: CancelID.load,
            cancelInFlight: true
        )
    }
}
