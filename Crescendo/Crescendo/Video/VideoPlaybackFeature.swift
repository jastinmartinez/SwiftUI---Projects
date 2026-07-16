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

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
