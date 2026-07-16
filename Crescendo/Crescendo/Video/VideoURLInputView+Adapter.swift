import ComposableArchitecture
import Foundation

extension VideoURLInputView.Model {
    /// Adapts reducer-owned Video state and actions into URL input presentation.
    @MainActor
    init(_ store: StoreOf<VideoPlaybackFeature>) {
        self.init(
            urlText: store.urlText,
            isLoading: store.isLoading,
            errorMessage: store.phase.errorMessage,
            isLoadDisabled: store.isLoading
                || store.urlText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
            onURLChanged: { store.send(.urlChanged($0)) },
            onLoad: { store.send(.loadSubmitted) }
        )
    }
}

// MARK: - Helpers

extension VideoPlaybackFeature.Phase {
    fileprivate var errorMessage: String? {
        guard case .failed(let error, _) = self else { return nil }
        return error.localizedMessage
    }
}

extension VideoPlaybackError {
    fileprivate var localizedMessage: String {
        switch self {
        case .emptyURL:
            Locs.Video.Error.emptyURL
        case .invalidURL:
            Locs.Video.Error.invalidURL
        case .unsupportedScheme:
            Locs.Video.Error.unsupportedScheme
        case .notPlayable:
            Locs.Video.Error.notPlayable
        case .loadFailed:
            Locs.Video.Error.loadFailed
        }
    }
}
