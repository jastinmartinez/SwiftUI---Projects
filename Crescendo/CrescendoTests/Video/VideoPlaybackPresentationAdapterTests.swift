import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct VideoPlaybackPresentationAdapterTests {
    @Test
    func loadingPhasePresentsLoadingAndDisablesLoadingAgain() {
        let store = makeStore(
            urlText: "https://example.com/video.mp4",
            phase: .loading(
                requestID: UUID(1),
                lastSnapshot: .idle
            )
        )

        let model = VideoURLInputView.Model(store)

        #expect(model.urlText == "https://example.com/video.mp4")
        #expect(model.isLoading)
        #expect(model.errorMessage == nil)
        #expect(model.isLoadDisabled)
    }

    @Test
    func loadAvailabilityTracksTrimmedIdleInput() {
        let whitespaceModel = VideoURLInputView.Model(
            makeStore(
                urlText: "  \n  ",
                phase: .observing(.idle)
            )
        )
        let nonemptyModel = VideoURLInputView.Model(
            makeStore(
                urlText: "https://example.com/video.mp4",
                phase: .observing(.idle)
            )
        )

        #expect(whitespaceModel.isLoadDisabled)
        #expect(!nonemptyModel.isLoadDisabled)
    }

    @Test
    func failedErrorsMapToLocalizedMessages() {
        let cases: [(VideoPlaybackError, String)] = [
            (.emptyURL, Locs.Video.Error.emptyURL),
            (.invalidURL, Locs.Video.Error.invalidURL),
            (.unsupportedScheme, Locs.Video.Error.unsupportedScheme),
            (.notPlayable, Locs.Video.Error.notPlayable),
            (.loadFailed, Locs.Video.Error.loadFailed),
        ]

        for (error, expectedMessage) in cases {
            let store = makeStore(
                urlText: "https://example.com/video.mp4",
                phase: .failed(
                    error,
                    lastSnapshot: .idle
                )
            )

            let model = VideoURLInputView.Model(store)

            #expect(model.errorMessage == expectedMessage)
        }
    }

    @Test
    func inputCallbacksForwardReducerActions() {
        let actions = LockIsolated<[VideoPlaybackFeature.Action]>([])
        let store: StoreOf<VideoPlaybackFeature> = Store(
            initialState: VideoPlaybackFeature.State(
                urlText: "",
                loadedVideoURL: nil,
                phase: .observing(.idle),
                observationID: nil
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
        let model = VideoURLInputView.Model(store)

        model.onURLChanged("https://example.com/video.mp4")
        model.onLoad()

        #expect(
            actions.value == [
                .urlChanged("https://example.com/video.mp4"),
                .loadSubmitted,
            ]
        )
    }

    // MARK: - Helpers

    private func makeStore(
        urlText: String,
        phase: VideoPlaybackFeature.Phase
    ) -> StoreOf<VideoPlaybackFeature> {
        Store(
            initialState: VideoPlaybackFeature.State(
                urlText: urlText,
                loadedVideoURL: nil,
                phase: phase,
                observationID: nil
            )
        ) {
            VideoPlaybackFeature()
        }
    }
}
