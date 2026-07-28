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
            makePlaybackStore(song: makeTrack(), status: status),
            providerName: nil
        )

        #expect(model.metadata.statusText == expectedText)
    }

    @Test(arguments: [
        (PlaybackPrimaryButtonView.Model.State.play, "play.fill"),
        (.pause, "pause.fill"),
    ])
    func primaryStateMapsSystemImage(
        state: PlaybackPrimaryButtonView.Model.State,
        expectedSystemImage: String
    ) {
        #expect(state.systemImage == expectedSystemImage)
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
            false
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
                song: makeTrack(),
                status: confirmedStatus,
                pendingStatusChange: .init(
                    requestID: UUID(0),
                    target: target
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
        let song = makeTrack(duration: 215)
        let store = makePlaybackStore(
            song: song,
            status: .playing,
            confirmedPosition: 43,
            timelineDuration: 215,
            timelineIsSeekable: true
        )
        let model = PlaybackView.Model(store, providerName: "Test Provider")

        #expect(model.metadata.title == song.title)
        #expect(model.metadata.artistName == song.artistName)
        #expect(model.metadata.providerAttribution == "Playing from Test Provider")
        #expect(model.artworkURL == song.artworkURL)
        #expect(model.timeline?.slider.value == 43)
        #expect(model.timeline?.slider.scale == .init(range: 0 ... 215))
        #expect(model.timeline?.elapsedTimeText == "0:43")
        #expect(model.timeline?.durationText == "3:35")
        #expect(model.controls.primary.state == .pause)
        #expect(model.controls.primary.isEnabled)
    }

    @Test
    func pendingInitialReplacementShowsTargetTrackWhileLoading() {
        let song = makeTrack()
        let tracks = IdentifiedArray(uniqueElements: [song])
        let store = makePlaybackStore(
            song: nil,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: tracks,
                targetTrackID: song.id
            )
        )

        let model = PlaybackView.Model(store, providerName: "Test Provider")

        #expect(model.metadata.title == song.title)
        #expect(model.metadata.artistName == song.artistName)
        #expect(model.artworkURL == song.artworkURL)
        #expect(model.metadata.statusText == Locs.Playback.Status.loading)
        #expect(!model.controls.primary.isEnabled)
    }

    @Test
    func confirmedTrackRemainsDisplayedWhileAnotherTrackIsPending() {
        let confirmedTrack = makeTrack(nativeID: "confirmed")
        let pendingTrack = Track(
            id: .init(providerID: "fake", nativeID: "pending"),
            title: "Pending",
            artistName: "Pending Artist",
            albumTitle: nil,
            artworkURL: URL(string: "https://example.com/pending"),
            duration: 120
        )
        let pendingQueue = IdentifiedArray(uniqueElements: [pendingTrack])
        let store = makePlaybackStore(
            song: confirmedTrack,
            status: .playing,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: pendingQueue,
                targetTrackID: pendingTrack.id
            )
        )

        let model = PlaybackView.Model(store, providerName: nil)

        #expect(model.metadata.title == confirmedTrack.title)
        #expect(model.metadata.artistName == confirmedTrack.artistName)
        #expect(model.artworkURL == confirmedTrack.artworkURL)
    }

    @Test
    func playbackFailureUsesInjectedPresentationStrings() {
        let track = makeTrack()
        let model = PlaybackView.Model(
            makePlaybackStore(
                song: track,
                failureNotice: PlaybackFailureNotice(
                    trackID: track.id,
                    failure: .preparationFailed
                )
            ),
            providerName: nil,
            strings: PlaybackView.Model.Strings(
                loading: "Preparing",
                resourceUnavailable: "Unavailable",
                unsupportedResource: "Unsupported",
                preparationFailed: "Preparation",
                playbackFailed: "Playback"
            )
        )

        #expect(model.metadata.statusText == "Preparation")
    }

    @Test
    func controlsUseInjectedStringsAndReducerOwnedPermissions() {
        let track = makeTrack()
        let store = makePlaybackStore(
            song: track,
            status: .playing,
            pendingStatusChange: .init(
                requestID: UUID(0),
                target: .paused
            )
        )
        let model = PlaybackControlsView.Model(
            store,
            strings: PlaybackControlsView.Model.Strings(
                play: "Start",
                pause: "Suspend",
                previous: "Back",
                next: "Forward",
                shuffle: "Randomize",
                repeatMode: "Cycle",
                modeOff: "Disabled",
                modeOn: "Enabled",
                modeAll: "Everything",
                modeOne: "Current"
            )
        )

        #expect(model.primary.accessibilityLabel == "Start")
        #expect(model.previous.accessibilityLabel == "Back")
        #expect(model.next.accessibilityLabel == "Forward")
        #expect(model.shuffle.accessibilityLabel == "Randomize")
        #expect(model.repeatMode.accessibilityLabel == "Cycle")
        #expect(!model.primary.isEnabled)
        #expect(model.previous.isEnabled == store.canRequestPrevious)
        #expect(model.next.isEnabled == store.canRequestNext)
        #expect(model.shuffle.isEnabled == store.canRequestShuffle)
        #expect(model.repeatMode.isEnabled == store.canRequestRepeat)
    }

    @Test
    func upNextProjectsEffectiveTrackOrder() throws {
        let first = makeTrack(nativeID: "first")
        let second = makeTrack(nativeID: "second")
        let third = makeTrack(nativeID: "third")
        let store = makePlaybackStore(
            song: first,
            queueTracks: [first, second, third],
            playbackOrder: [first.id, third.id, second.id]
        )

        let model = try #require(
            PlaybackUpNextView.Model(store, title: "Coming next")
        )

        #expect(model.title == "Coming next")
        #expect(model.tracks.map(\.id) == [third.id, second.id])
        #expect(model.tracks.allSatisfy { $0.accessory == .none })
    }

    @Test
    func upNextIsHiddenAtTheQueueBoundary() {
        let onlyTrack = makeTrack(nativeID: "only")
        let store = makePlaybackStore(song: onlyTrack)

        #expect(
            PlaybackUpNextView.Model(store, title: "Coming next")
                .map { _ in true } == nil
        )
    }

    @Test(arguments: [
        (
            PlaybackFailure.resourceUnavailable,
            Locs.Playback.Failure.resourceUnavailable
        ),
        (.unsupportedResource, Locs.Playback.Failure.unsupportedResource),
        (.preparationFailed, Locs.Playback.Failure.preparationFailed),
        (.playbackFailed, Locs.Playback.Failure.playbackFailed),
    ])
    func playbackFailureMapsToLocalizedStatus(
        failure: PlaybackFailure,
        expectedText: String
    ) {
        let song = makeTrack()
        let model = PlaybackView.Model(
            makePlaybackStore(
                song: song,
                failureNotice: PlaybackFailureNotice(
                    trackID: song.id,
                    failure: failure
                )
            ),
            providerName: nil
        )

        #expect(model.metadata.statusText == expectedText)
    }

    @Test
    func fullTimelineProjectsSliderControlsAndLocalizedLabels() throws {
        let song = makeTrack(duration: 215)
        let actions = LockIsolated<[PlaybackFeature.Action]>([])
        let store = makeActionRecordingStore(
            song: song,
            timelineDuration: 215,
            timelineIsSeekable: true,
            actions: actions
        )
        let timeline = try #require(PlaybackTimelineView.Model(store))
        let skipControls = PlaybackSkipControlsView.Model(store)
        let utilityControls = PlaybackUtilityControlsView.Model(store)

        #expect(timeline.slider.value == 43)
        #expect(timeline.slider.scale == .init(range: 0 ... 215))
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
            song: makeTrack(duration: 215),
            confirmedPosition: 43,
            timelineDuration: 215,
            timelineIsSeekable: true,
            timelineInteraction: interaction
        )

        let timeline = try #require(PlaybackTimelineView.Model(store))
        #expect(timeline.slider.value == 60)
    }

    @Test(arguments: [TimeInterval?(180), TimeInterval?.none])
    func observedDurationControlsPresentationWhenCatalogDurationDiffersOrIsMissing(
        catalogDuration: TimeInterval?
    ) async throws {
        let song = makeTrack(duration: catalogDuration)
        let store = makePlaybackStore(
            song: song,
            status: .playing,
            confirmedPosition: 110
        )

        await store.send(
            .reconcileSnapshot(
                PlaybackSnapshot(
                    currentTrackID: song.id,
                    status: .playing,
                    position: 110,
                    duration: 120,
                    isSeekable: true
                )
            )
        ).finish()

        let timeline = try #require(PlaybackTimelineView.Model(store))
        #expect(timeline.slider.scale == .init(range: 0 ... 120))
        #expect(timeline.durationText == "2:00")
    }

    @Test
    func catalogDurationAloneDoesNotCreateTimelineOrEnableSeeking() {
        let store = makePlaybackStore(song: makeTrack(duration: 215))

        #expect(store.timeline.duration == nil)
        #expect(!store.timeline.isSeekable)
        #expect(!store.canRequestSeek)
        #expect(PlaybackTimelineView.Model(store).map { _ in true } == nil)
        #expect(
            PlaybackSkipControlsView.Model(store).controls.allSatisfy {
                !$0.isEnabled
            }
        )
    }

    @Test
    func timelineClampsPositionAndRequiresPositiveDuration() throws {
        let negativePosition = makePlaybackStore(
            song: makeTrack(duration: 215),
            confirmedPosition: -1,
            timelineDuration: 215
        )
        let overflow = makePlaybackStore(
            song: makeTrack(duration: 215),
            confirmedPosition: 216,
            timelineDuration: 215
        )
        let missing = makePlaybackStore(
            song: makeTrack(),
            timelineDuration: nil
        )
        let zero = makePlaybackStore(
            song: makeTrack(),
            timelineDuration: 0
        )
        let negativeDuration = makePlaybackStore(
            song: makeTrack(),
            timelineDuration: -1
        )

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
    func confirmedNonseekableTimelineStaysVisibleButDisabled() throws {
        let store = makePlaybackStore(
            song: makeTrack(duration: 215),
            timelineDuration: 215,
            timelineIsSeekable: false
        )

        let timeline = try #require(PlaybackTimelineView.Model(store))
        let skipControls = PlaybackSkipControlsView.Model(store)
        #expect(!timeline.slider.isEnabled)
        #expect(skipControls.controls.allSatisfy { !$0.isEnabled })
    }

    @Test
    func controlAdapterCallbacksForwardPresentationActions() throws {
        let song = makeTrack(duration: 215)
        let actions = LockIsolated<[PlaybackFeature.Action]>([])
        let store = makeActionRecordingStore(
            song: song,
            timelineDuration: 215,
            timelineIsSeekable: true,
            actions: actions
        )
        let model = PlaybackView.Model(store, providerName: nil)
        let skipControls = try #require(model.skipControls)

        model.controls.shuffle.perform()
        model.controls.previous.perform()
        model.controls.primary.perform()
        model.controls.next.perform()
        model.controls.repeatMode.perform()
        skipControls.controls[0].perform()
        skipControls.controls[1].perform()
        model.utilityControls.controls[0].perform()
        model.utilityControls.controls[1].perform()

        #expect(
            actions.value.prefix(5) == [
                .shuffleTapped,
                .previousTapped,
                .playPauseTapped,
                .nextTapped,
                .repeatTapped,
            ]
        )
        #expect(
            actions.value == [
                .shuffleTapped,
                .previousTapped,
                .playPauseTapped,
                .nextTapped,
                .repeatTapped,
                .seekBackwardTapped,
                .seekForwardTapped,
                .restartTapped,
                .stopTapped,
            ]
        )
    }

    @Test
    func controlsProjectReducerOwnedPermissions() {
        let song = makeTrack()
        let tracks = IdentifiedArray(uniqueElements: [song])
        let store = makePlaybackStore(
            song: song,
            status: .playing,
            pendingStatusChange: .init(requestID: UUID(0), target: .paused)
        )
        let model = PlaybackView.Model(store, providerName: nil)

        #expect(!model.controls.primary.isEnabled)
        #expect(!model.utilityControls.controls[1].isEnabled)

        let transitioningStore = makePlaybackStore(
            song: song,
            status: .playing,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: tracks,
                targetTrackID: song.id
            )
        )
        let transitioningModel = PlaybackView.Model(
            transitioningStore,
            providerName: nil
        )
        #expect(!transitioningModel.controls.primary.isEnabled)
        #expect(transitioningModel.utilityControls.controls[1].isEnabled)

        let unconfirmedStore = makePlaybackStore(
            song: nil,
            status: .stopped,
            pendingPlaybackTransition: PendingPlaybackTransition(
                requestID: UUID(0),
                queue: tracks,
                targetTrackID: song.id
            )
        )
        let unconfirmedModel = PlaybackView.Model(
            unconfirmedStore,
            providerName: nil
        )
        #expect(!unconfirmedModel.controls.primary.isEnabled)
        #expect(!unconfirmedModel.utilityControls.controls[1].isEnabled)
    }

    @Test
    func queueControlsProjectPermissionsLabelsAndSymbols() {
        let song = makeTrack()
        let queueTracks = [
            makeTrack(nativeID: "previous"),
            song,
            makeTrack(nativeID: "next"),
        ]
        let enabledModel = PlaybackView.Model(
            makePlaybackStore(song: song, queueTracks: queueTracks),
            providerName: nil
        )
        let resettingModel = PlaybackView.Model(
            makePlaybackStore(
                song: song,
                queueTracks: queueTracks,
                pendingProviderReset: .init(
                    requestID: UUID(0),
                    providerID: song.id.providerID,
                    capabilities: .allEnabled
                )
            ),
            providerName: nil
        )

        #expect(enabledModel.controls.previous.isEnabled)
        #expect(enabledModel.controls.next.isEnabled)
        #expect(!resettingModel.controls.previous.isEnabled)
        #expect(!resettingModel.controls.next.isEnabled)
        #expect(enabledModel.controls.previous.systemImage == "backward.fill")
        #expect(enabledModel.controls.next.systemImage == "forward.fill")
        #expect(enabledModel.controls.primary.state == .play)
        #expect(
            enabledModel.controls.previous.accessibilityLabel == "Previous track"
        )
        #expect(enabledModel.controls.next.accessibilityLabel == "Next track")
        let utilityTitles = enabledModel.utilityControls.controls.map(\.title)
        #expect(utilityTitles == ["Restart", "Stop"])
    }

    @Test
    func queueModeControlsProjectConfirmedStateAndPermissions() {
        let store = makePlaybackStore(
            song: makeTrack(),
            repeatMode: .one,
            shuffleMode: .tracks
        )
        let controls = PlaybackControlsView.Model(store)

        #expect(controls.shuffle.systemImage == "shuffle")
        #expect(controls.shuffle.isSelected)
        #expect(controls.shuffle.accessibilityValue == Locs.Playback.Mode.on)
        #expect(controls.shuffle.isEnabled)
        #expect(controls.repeatMode.systemImage == "repeat.1")
        #expect(controls.repeatMode.isSelected)
        #expect(controls.repeatMode.accessibilityValue == Locs.Playback.Mode.one)
        #expect(controls.repeatMode.isEnabled)
    }

    @Test(arguments: [
        (PlaybackRepeatMode.off, "repeat", false, Locs.Playback.Mode.off),
        (.all, "repeat", true, Locs.Playback.Mode.all),
        (.one, "repeat.1", true, Locs.Playback.Mode.one),
    ])
    func repeatControlProjectsConfirmedMode(
        repeatMode: PlaybackRepeatMode,
        expectedSystemImage: String,
        expectedIsSelected: Bool,
        expectedAccessibilityValue: String
    ) {
        let controls = PlaybackControlsView.Model(
            makePlaybackStore(song: makeTrack(), repeatMode: repeatMode)
        )

        let accessibilityValue = controls.repeatMode.accessibilityValue
        #expect(controls.repeatMode.systemImage == expectedSystemImage)
        #expect(controls.repeatMode.isSelected == expectedIsSelected)
        #expect(accessibilityValue == expectedAccessibilityValue)
    }

    @Test
    func providerResetPolicyDisablesEveryCommandAdapter() throws {
        let song = makeTrack()
        let pendingProviderReset = PlaybackFeature.PendingProviderReset(
            requestID: UUID(0),
            providerID: "replacement",
            capabilities: .allEnabled
        )
        let store = makePlaybackStore(
            song: song,
            status: .playing,
            confirmedPosition: 43,
            timelineDuration: 180,
            timelineIsSeekable: true,
            pendingProviderReset: pendingProviderReset
        )

        let controls = PlaybackControlsView.Model(store)
        let nowPlaying = try #require(PlaybackNowPlayingView.Model(store))
        let skipControls = PlaybackSkipControlsView.Model(store)
        let timeline = try #require(PlaybackTimelineView.Model(store))
        let utilityControls = PlaybackUtilityControlsView.Model(store)

        #expect(!controls.shuffle.isEnabled)
        #expect(!controls.previous.isEnabled)
        #expect(!controls.primary.isEnabled)
        #expect(!controls.next.isEnabled)
        #expect(!controls.repeatMode.isEnabled)
        #expect(!nowPlaying.isPlayPauseEnabled)
        #expect(skipControls.controls.allSatisfy { !$0.isEnabled })
        #expect(!timeline.slider.isEnabled)
        #expect(utilityControls.controls.allSatisfy { !$0.isEnabled })
    }

    @Test
    func commandAndStatusWordsRemainDistinct() {
        #expect(Locs.Playback.play != Locs.Playback.Status.playing)
        #expect(Locs.Playback.pause != Locs.Playback.Status.paused)
        #expect(Locs.Playback.stop != Locs.Playback.Status.stopped)
    }

    // MARK: - Helpers

    private func makePlaybackStore(
        song: Track?,
        queueTracks: [Track]? = nil,
        status: PlaybackStatus = .idle,
        failureNotice: PlaybackFailureNotice? = nil,
        playbackEligibility: CatalogPlaybackEligibility = .eligible,
        capabilities: MusicProviderCapabilities = .allEnabled,
        confirmedPosition: TimeInterval = 0,
        timelineDuration: TimeInterval? = nil,
        timelineIsSeekable: Bool = false,
        timelineInteraction: PlaybackTimelineFeature.Interaction = .idle,
        repeatMode: PlaybackRepeatMode = .off,
        shuffleMode: PlaybackShuffleMode = .off,
        pendingPlaybackTransition: PendingPlaybackTransition? = nil,
        pendingStatusChange: PlaybackFeature.PendingStatusChange? = nil,
        pendingProviderReset: PlaybackFeature.PendingProviderReset? = nil,
        playbackOrder: [TrackID]? = nil
    ) -> StoreOf<PlaybackFeature> {
        let tracks = IdentifiedArray(
            uniqueElements: queueTracks ?? song.map { [$0] } ?? []
        )
        return Store(
            initialState: PlaybackFeature.State(
                providerID: song?.id.providerID ?? "fake",
                queue: PlaybackQueueFeature.State(
                    tracks: tracks,
                    playbackOrder: PlaybackQueueOrder(
                        trackIDs: playbackOrder ?? Array(tracks.ids)
                    ),
                    currentTrackID: song?.id,
                    repeatMode: repeatMode,
                    shuffleMode: shuffleMode
                ),
                status: status,
                failureNotice: failureNotice,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: confirmedPosition,
                    duration: timelineDuration,
                    isSeekable: timelineIsSeekable,
                    interaction: timelineInteraction
                ),
                pendingPlaybackTransition: pendingPlaybackTransition,
                pendingStatusChange: pendingStatusChange,
                pendingProviderReset: pendingProviderReset,
                isPlayerPresented: false
            )
        ) {
            PlaybackFeature()
        }
    }

    private func makeActionRecordingStore(
        song: Track,
        timelineDuration: TimeInterval,
        timelineIsSeekable: Bool,
        actions: LockIsolated<[PlaybackFeature.Action]>
    ) -> StoreOf<PlaybackFeature> {
        let tracks = IdentifiedArray(uniqueElements: [song])
        return Store(
            initialState: PlaybackFeature.State(
                providerID: song.id.providerID,
                queue: .init(
                    tracks: tracks,
                    playbackOrder: PlaybackQueueOrder(trackIDs: Array(tracks.ids)),
                    currentTrackID: song.id,
                    repeatMode: .off,
                    shuffleMode: .off
                ),
                status: .playing,
                failureNotice: nil,
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: .init(
                    confirmedPosition: 43,
                    duration: timelineDuration,
                    isSeekable: timelineIsSeekable,
                    interaction: .idle
                ),
                pendingPlaybackTransition: nil,
                pendingStatusChange: nil,
                pendingProviderReset: nil,
                isPlayerPresented: false
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
    }

    private func makeTrack(
        nativeID: String = "song",
        duration: TimeInterval? = 180
    ) -> Track {
        Track(
            id: .init(providerID: "fake", nativeID: nativeID),
            title: "Song",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: URL(string: "https://example.com/artwork"),
            duration: duration
        )
    }
}
