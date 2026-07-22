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

    @Test(arguments: [
        (
            PlaybackStatus.playing,
            PlaybackFeature.PendingStatusChange.Target.paused,
            Locs.Playback.Status.paused,
            PlaybackPrimaryButtonView.Model.State.play,
            false
        ),
        (
            PlaybackStatus.paused,
            PlaybackFeature.PendingStatusChange.Target.playing,
            Locs.Playback.Status.playing,
            PlaybackPrimaryButtonView.Model.State.pause,
            false
        ),
        (
            PlaybackStatus.playing,
            PlaybackFeature.PendingStatusChange.Target.stopped,
            Locs.Playback.Status.stopped,
            PlaybackPrimaryButtonView.Model.State.play,
            true
        ),
    ])
    func pendingStatusTargetProjectsImmediatePresentation(
        confirmedStatus: PlaybackStatus,
        target: PlaybackFeature.PendingStatusChange.Target,
        expectedStatusText: String,
        expectedPrimaryState: PlaybackPrimaryButtonView.Model.State,
        expectedIsPrimaryEnabled: Bool
    ) {
        let model = PlaybackView.Model(
            makePlaybackStore(
                song: makeSong(),
                status: confirmedStatus,
                pendingOperation: .statusChange(
                    .init(requestID: UUID(0), target: target)
                )
            ),
            providerName: nil
        )

        #expect(model.metadata.statusText == expectedStatusText)
        #expect(model.controls.primary.state == expectedPrimaryState)
        #expect(model.controls.primary.isEnabled == expectedIsPrimaryEnabled)
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
        #expect(model.timeline?.slider.value == 43)
        #expect(model.timeline?.slider.scale == .init(range: 0...215))
        #expect(model.timeline?.elapsedTimeText == "0:43")
        #expect(model.timeline?.durationText == "3:35")
        #expect(model.controls.primary.state == .pause)
        #expect(model.controls.primary.isEnabled)
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
        #expect(!model.controls.primary.isEnabled)
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
    func fullTimelineProjectsSliderControlsAndLocalizedLabels() throws {
        let song = makeSong(duration: 215)
        let actions = LockIsolated<[PlaybackFeature.Action]>([])
        let store = makeActionRecordingStore(song: song, actions: actions)
        let timeline = try #require(PlaybackTimelineView.Model(store))
        let skipControls = PlaybackSkipControlsView.Model(store)
        let utilityControls = PlaybackUtilityControlsView.Model(store)

        #expect(timeline.slider.value == 43)
        #expect(timeline.slider.scale == .init(range: 0...215))
        #expect(timeline.slider.isEnabled)
        #expect(timeline.slider.strings.accessibilityLabel == "Playback position")
        #expect(timeline.slider.strings.accessibilityValue == "0:43 of 3:35")
        #expect(timeline.elapsedTimeText == "0:43")
        #expect(timeline.durationText == "3:35")
        #expect(skipControls.controls.map(\.id) == [.backward, .forward])
        #expect(
            skipControls.controls.map(\.systemImage) == [
                "gobackward.15",
                "goforward.15",
            ]
        )
        #expect(
            skipControls.controls.map(\.accessibilityLabel) == [
                "Back 15 seconds",
                "Forward 15 seconds",
            ]
        )
        #expect(skipControls.controls.allSatisfy { $0.isEnabled })
        #expect(utilityControls.controls.map(\.id) == [.restart, .stop])
        #expect(
            utilityControls.controls.map(\.systemImage) == [
                "arrow.counterclockwise",
                "stop.fill",
            ]
        )

        timeline.slider.onValueChanged(30)
        timeline.slider.onInteractionEnded()
        for control in skipControls.controls {
            control.perform()
        }
        for control in utilityControls.controls {
            control.perform()
        }

        #expect(
            actions.value == [
                .timelinePositionChanged(30),
                .timelineInteractionEnded,
                .seekBackwardTapped,
                .seekForwardTapped,
                .restartTapped,
                .stopTapped,
            ]
        )
    }

    @Test(arguments: [
        PlaybackTimelineFeature.Interaction.dragging(position: 60),
        .seeking(requestID: UUID(0), position: 60),
    ])
    func timelineInteractionOverridesConfirmedPosition(
        interaction: PlaybackTimelineFeature.Interaction
    ) throws {
        let store = makePlaybackStore(
            song: makeSong(duration: 215),
            confirmedPosition: 43,
            timelineInteraction: interaction
        )

        let timeline = try #require(PlaybackTimelineView.Model(store))
        #expect(timeline.slider.value == 60)
    }

    @Test
    func timelineClampsPositionAndRequiresPositiveDuration() throws {
        let negativePosition = makePlaybackStore(
            song: makeSong(duration: 215),
            confirmedPosition: -1
        )
        let overflow = makePlaybackStore(
            song: makeSong(duration: 215),
            confirmedPosition: 216
        )
        let missing = makePlaybackStore(song: makeSong(duration: nil))
        let zero = makePlaybackStore(song: makeSong(duration: 0))
        let negativeDuration = makePlaybackStore(song: makeSong(duration: -1))

        let negativePositionTimeline = try #require(
            PlaybackTimelineView.Model(negativePosition)
        )
        let overflowTimeline = try #require(
            PlaybackTimelineView.Model(overflow)
        )
        #expect(negativePositionTimeline.slider.value == 0)
        #expect(overflowTimeline.slider.value == 215)
        #expect(
            PlaybackTimelineView.Model(missing).map { _ in true } == nil
        )
        #expect(
            PlaybackTimelineView.Model(zero).map { _ in true } == nil
        )
        #expect(
            PlaybackTimelineView.Model(negativeDuration).map { _ in true } == nil
        )
    }

    @Test
    func unsupportedSeekingKeepsTimelineVisibleButDisabled() throws {
        let capabilities = MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: false,
            supportsQueueReplacement: true,
            supportsQueueTransitions: true
        )
        let store = makePlaybackStore(
            song: makeSong(duration: 215),
            capabilities: capabilities
        )

        let timeline = try #require(PlaybackTimelineView.Model(store))
        let skipControls = PlaybackSkipControlsView.Model(store)
        #expect(!timeline.slider.isEnabled)
        #expect(skipControls.controls.allSatisfy { !$0.isEnabled })
    }

    @Test
    func controlAdapterCallbacksForwardPresentationActions() throws {
        let song = makeSong(duration: 215)
        let actions = LockIsolated<[PlaybackFeature.Action]>([])
        let store = makeActionRecordingStore(song: song, actions: actions)
        let model = PlaybackView.Model(store, providerName: nil)
        let skipControls = try #require(model.skipControls)

        skipControls.controls[0].perform()
        skipControls.controls[1].perform()
        model.controls.previous.perform()
        model.controls.primary.perform()
        model.controls.next.perform()
        model.utilityControls.controls[0].perform()
        model.utilityControls.controls[1].perform()

        #expect(
            actions.value == [
                .seekBackwardTapped,
                .seekForwardTapped,
                .previousTapped,
                .playPauseTapped,
                .nextTapped,
                .restartTapped,
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

        #expect(!model.controls.primary.isEnabled)
        #expect(!model.utilityControls.controls[1].isEnabled)

        let replacingStore = makePlaybackStore(
            song: nil,
            status: .stopped,
            pendingOperation: .queueReplacement(
                .init(requestID: UUID(0), songs: songs, startingItemID: song.id)
            )
        )
        let replacingModel = PlaybackView.Model(replacingStore, providerName: nil)
        #expect(!replacingModel.controls.primary.isEnabled)
        #expect(replacingModel.utilityControls.controls[1].isEnabled)
    }

    @Test
    func queueControlsProjectPermissionsLabelsAndSymbols() {
        let song = makeSong()
        let enabledModel = PlaybackView.Model(
            makePlaybackStore(song: song),
            providerName: nil
        )
        let pendingModel = PlaybackView.Model(
            makePlaybackStore(
                song: song,
                pendingQueueTransition: .init(
                    requestID: UUID(0),
                    direction: .next
                )
            ),
            providerName: nil
        )

        #expect(enabledModel.controls.previous.isEnabled)
        #expect(enabledModel.controls.next.isEnabled)
        #expect(!pendingModel.controls.previous.isEnabled)
        #expect(!pendingModel.controls.next.isEnabled)
        #expect(
            enabledModel.controls.previous.systemImage
                == "backward.fill"
        )
        #expect(
            enabledModel.controls.next.systemImage
                == "forward.fill"
        )
        #expect(enabledModel.controls.primary.state == .play)
        #expect(
            enabledModel.controls.previous.accessibilityLabel
                == "Previous track"
        )
        #expect(
            enabledModel.controls.next.accessibilityLabel
                == "Next track"
        )
        #expect(
            enabledModel.utilityControls.controls.map(\.title)
                == ["Restart", "Stop"]
        )
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
        timelineInteraction: PlaybackTimelineFeature.Interaction = .idle,
        pendingQueueTransition: PlaybackQueueFeature.PendingQueueTransition? = nil,
        pendingOperation: PlaybackFeature.PendingOperation? = nil
    ) -> StoreOf<PlaybackFeature> {
        let songs = IdentifiedArray(uniqueElements: song.map { [$0] } ?? [])
        return Store(
            initialState: PlaybackFeature.State(
                providerID: song?.id.providerID ?? "fake",
                queue: PlaybackQueueFeature.State(
                    songs: songs,
                    currentItemID: song?.id,
                    pendingQueueTransition: pendingQueueTransition
                ),
                status: status,
                failure: failure,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: confirmedPosition,
                    interaction: timelineInteraction
                ),
                pendingOperation: pendingOperation,
                pendingReset: nil,
                isPlayerPresented: false
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
                queue: .init(
                    songs: songs,
                    currentItemID: song.id,
                    pendingQueueTransition: nil
                ),
                status: .playing,
                failure: nil,
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: .init(
                    confirmedPosition: 43,
                    interaction: .idle
                ),
                pendingOperation: nil,
                pendingReset: nil,
                isPlayerPresented: false
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
