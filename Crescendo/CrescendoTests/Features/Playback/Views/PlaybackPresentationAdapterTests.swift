import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackPresentationAdapterTests {
    @Test(arguments: [
        (PlaybackStatus.idle, Locs.Playback.Status.idle),
        (.playing, Locs.Playback.Status.playing),
        (.paused, Locs.Playback.Status.paused),
        (.stopped, Locs.Playback.Status.stopped),
    ])
    func confirmedStatusMapsToLocalizedPresentation(
        status: PlaybackStatus,
        expectedText: String
    ) {
        let model = PlaybackView.Model(
            makePlaybackStore(song: makeSong(), status: status),
            providerName: nil
        )

        #expect(model.metadata.statusText == expectedText)
    }

    @Test
    func confirmedQueueMapsMetadataTimelineAndControls() {
        let song = makeSong(duration: 215)
        let store = makePlaybackStore(
            song: song,
            status: .playing,
            confirmedPosition: 43
        )
        let model = PlaybackView.Model(store, providerName: "Apple Music")

        #expect(model.metadata.title == song.title)
        #expect(model.metadata.artistName == song.artistName)
        #expect(model.metadata.providerAttribution == "Playing from Apple Music")
        #expect(model.artworkURL == song.artworkURL)
        #expect(model.timeline?.position == 43)
        #expect(model.timeline?.range == 0...215)
        #expect(model.timeline?.elapsedTimeText == "0:43")
        #expect(model.timeline?.durationText == "3:35")
        #expect(model.controls.primaryAction == .pause)
        #expect(model.controls.isPrimaryEnabled)
        #expect(model.eligibility.presentation == .hidden)
    }

    @Test
    func pendingInitialReplacementShowsLoadingWithoutSongMetadata() {
        let song = makeSong()
        let songs = IdentifiedArray(uniqueElements: [song])
        let store = makePlaybackStore(
            song: nil,
            pendingOperation: .queueReplacement(
                .init(
                    requestID: UUID(0),
                    songs: songs,
                    startingItemID: song.id
                )
            )
        )

        let model = PlaybackView.Model(store, providerName: "Apple Music")

        #expect(model.metadata.title == Locs.Playback.noSelection)
        #expect(model.metadata.artistName == nil)
        #expect(model.artworkURL == nil)
        #expect(model.metadata.statusText == Locs.Playback.Status.loading)
        #expect(!model.controls.isPrimaryEnabled)
    }

    @Test(arguments: [
        (MusicProviderError.unavailable, Locs.Playback.Status.unavailable),
        (.playbackFailed, Locs.Playback.Status.failed),
    ])
    func playbackFailureMapsToLocalizedStatus(
        failure: MusicProviderError,
        expectedText: String
    ) {
        let model = PlaybackView.Model(
            makePlaybackStore(song: makeSong(), failure: failure),
            providerName: nil
        )

        #expect(model.metadata.statusText == expectedText)
    }

    @Test
    func timelineFactoryUsesConfirmedPositionAndInjectedStrings() throws {
        let model = try #require(
            PlaybackTimelineView.Model.make(
                duration: 215,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: 43,
                    interaction: .idle
                ),
                supportsSeeking: true,
                strings: { elapsedTime, durationTime in
                    PlaybackTimelineView.Model.Strings(
                        accessibilityLabel: "Custom position",
                        accessibilityValue:
                            "\(elapsedTime) elapsed from \(durationTime)"
                    )
                },
                onPositionChanged: { _ in },
                onDragEnded: {}
            )
        )

        #expect(model.position == 43)
        #expect(model.strings.accessibilityLabel == "Custom position")
        #expect(model.strings.accessibilityValue == "0:43 elapsed from 3:35")
    }

    @Test(arguments: [
        PlaybackTimelineFeature.Interaction.dragging(position: 60),
        .seeking(requestID: UUID(0), position: 60),
    ])
    func timelineInteractionOverridesConfirmedPosition(
        interaction: PlaybackTimelineFeature.Interaction
    ) throws {
        let model = try #require(
            PlaybackTimelineView.Model.make(
                duration: 215,
                timeline: .init(
                    confirmedPosition: 43,
                    interaction: interaction
                ),
                supportsSeeking: true,
                strings: { _, _ in
                    .init(accessibilityLabel: "", accessibilityValue: "")
                },
                onPositionChanged: { _ in },
                onDragEnded: {}
            )
        )

        #expect(model.position == 60)
    }

    @Test
    func timelineClampsAndOmitsUnsupportedValues() {
        let negative = PlaybackTimelineView.Model.make(
            duration: 215,
            timeline: .init(confirmedPosition: -1, interaction: .idle),
            supportsSeeking: true,
            strings: { _, _ in
                .init(accessibilityLabel: "", accessibilityValue: "")
            },
            onPositionChanged: { _ in },
            onDragEnded: {}
        )
        let overflow = PlaybackTimelineView.Model.make(
            duration: 215,
            timeline: .init(confirmedPosition: 216, interaction: .idle),
            supportsSeeking: true,
            strings: { _, _ in
                .init(accessibilityLabel: "", accessibilityValue: "")
            },
            onPositionChanged: { _ in },
            onDragEnded: {}
        )
        let unsupported = PlaybackTimelineView.Model.make(
            duration: 215,
            timeline: .init(confirmedPosition: 43, interaction: .idle),
            supportsSeeking: false,
            strings: { _, _ in
                .init(accessibilityLabel: "", accessibilityValue: "")
            },
            onPositionChanged: { _ in },
            onDragEnded: {}
        )

        #expect(negative?.position == 0)
        #expect(overflow?.position == 215)
        #expect(unsupported == nil)
    }

    @Test
    func adapterCallbacksForwardPresentationActions() {
        let song = makeSong(duration: 215)
        let actions = LockIsolated<[PlaybackFeature.Action]>([])
        let store = makeActionRecordingStore(song: song, actions: actions)
        let model = PlaybackView.Model(store, providerName: nil)

        model.timeline?.onPositionChanged(30)
        model.timeline?.onDragEnded()
        model.controls.onPrimaryAction()
        model.controls.onStop()

        #expect(
            actions.value == [
                .timeline(.positionChanged(30)),
                .timeline(.dragEnded),
                .playPauseTapped,
                .stopTapped,
            ]
        )
    }

    @Test
    func controlsProjectReducerOwnedPermissions() {
        let song = makeSong()
        let songs = IdentifiedArray(uniqueElements: [song])
        let store = makePlaybackStore(
            song: song,
            status: .playing,
            pendingOperation: .statusChange(
                .init(requestID: UUID(0), target: .paused)
            )
        )
        let model = PlaybackView.Model(store, providerName: nil)

        #expect(!model.controls.isPrimaryEnabled)
        #expect(!model.controls.isStopEnabled)

        let replacingStore = makePlaybackStore(
            song: nil,
            status: .stopped,
            pendingOperation: .queueReplacement(
                .init(requestID: UUID(0), songs: songs, startingItemID: song.id)
            )
        )
        let replacingModel = PlaybackView.Model(replacingStore, providerName: nil)
        #expect(!replacingModel.controls.isPrimaryEnabled)
        #expect(replacingModel.controls.isStopEnabled)
    }

    @Test(arguments: [
        (
            CatalogPlaybackEligibility.eligible,
            PlaybackEligibilityNoticeView.Model.Presentation.hidden
        ),
        (.ineligible, .subscriptionRequired),
        (.unknown, .availabilityUnknown),
    ])
    func playbackEligibilityMapsToPresentation(
        eligibility: CatalogPlaybackEligibility,
        expectedPresentation: PlaybackEligibilityNoticeView.Model.Presentation
    ) {
        let model = PlaybackEligibilityNoticeView.Model(
            makePlaybackStore(
                song: makeSong(),
                playbackEligibility: eligibility
            )
        )

        #expect(model.presentation == expectedPresentation)
    }

    @Test
    func commandAndStatusWordsRemainDistinct() {
        #expect(Locs.Playback.play != Locs.Playback.Status.playing)
        #expect(Locs.Playback.pause != Locs.Playback.Status.paused)
        #expect(Locs.Playback.stop != Locs.Playback.Status.stopped)
    }

    // MARK: - Helpers

    private func makePlaybackStore(
        song: SongSummary?,
        status: PlaybackStatus = .idle,
        failure: MusicProviderError? = nil,
        playbackEligibility: CatalogPlaybackEligibility = .eligible,
        capabilities: MusicProviderCapabilities = .allEnabled,
        confirmedPosition: TimeInterval = 0,
        pendingOperation: PlaybackFeature.PendingOperation? = nil
    ) -> StoreOf<PlaybackFeature> {
        let songs = IdentifiedArray(uniqueElements: song.map { [$0] } ?? [])
        return Store(
            initialState: PlaybackFeature.State(
                providerID: song?.id.providerID ?? "fake",
                queue: PlaybackQueueFeature.State(
                    songs: songs,
                    currentItemID: song?.id
                ),
                status: status,
                failure: failure,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: confirmedPosition,
                    interaction: .idle
                ),
                pendingOperation: pendingOperation
            )
        ) {
            PlaybackFeature()
        }
    }

    private func makeActionRecordingStore(
        song: SongSummary,
        actions: LockIsolated<[PlaybackFeature.Action]>
    ) -> StoreOf<PlaybackFeature> {
        let songs = IdentifiedArray(uniqueElements: [song])
        return Store(
            initialState: PlaybackFeature.State(
                providerID: song.id.providerID,
                queue: .init(songs: songs, currentItemID: song.id),
                status: .playing,
                failure: nil,
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: .init(
                    confirmedPosition: 43,
                    interaction: .idle
                ),
                pendingOperation: nil
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
    }

    private func makeSong(duration: TimeInterval? = 180) -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "song"),
            title: "Song",
            artistName: "Artist",
            artworkURL: URL(string: "https://example.com/artwork"),
            duration: duration
        )
    }
}
