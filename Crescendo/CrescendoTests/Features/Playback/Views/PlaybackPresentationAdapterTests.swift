import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackPresentationAdapterTests {
    @Test
    func dismissHandleRoutesPresentationThroughPlayback() {
        let store = makePlaybackStore(song: makeTrack())
        store.send(.setPlayerPresented(true))
        let model = PlaybackDismissHandleView.Model(store)

        #expect(store.isPlayerPresented)
        #expect(model.accessibilityLabel == "Dismiss player")

        model.onDismiss()

        #expect(!store.isPlayerPresented)
    }

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
        let model = PlaybackCurrentTrackView.Model(
            makePlaybackStore(song: makeTrack(), status: status)
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
            PlaybackSessionReducer.PendingStatusChange.Target.paused,
            Locs.Playback.Status.paused,
            PlaybackPrimaryButtonView.Model.State.play,
            false
        ),
        (
            PlaybackStatus.paused,
            PlaybackSessionReducer.PendingStatusChange.Target.playing,
            Locs.Playback.Status.playing,
            PlaybackPrimaryButtonView.Model.State.pause,
            false
        ),
        (
            PlaybackStatus.playing,
            PlaybackSessionReducer.PendingStatusChange.Target.stopped,
            Locs.Playback.Status.stopped,
            PlaybackPrimaryButtonView.Model.State.play,
            false
        ),
    ])
    func pendingStatusTargetProjectsImmediatePresentation(
        confirmedStatus: PlaybackStatus,
        target: PlaybackSessionReducer.PendingStatusChange.Target,
        expectedStatusText: String,
        expectedPrimaryState: PlaybackPrimaryButtonView.Model.State,
        expectedIsPrimaryEnabled: Bool
    ) {
        let store = makePlaybackStore(
            song: makeTrack(),
            status: confirmedStatus,
            pendingStatusChange: .init(
                requestID: UUID(0),
                target: target
            )
        )
        let currentTrack = PlaybackCurrentTrackView.Model(store)
        let controls = PlaybackControlsView.Model(store)

        #expect(currentTrack.metadata.statusText == expectedStatusText)
        #expect(controls.primary.state == expectedPrimaryState)
        #expect(controls.primary.isEnabled == expectedIsPrimaryEnabled)
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
        let currentTrack = PlaybackCurrentTrackView.Model(store)
        let timeline = PlaybackTimelineView.Model(store)
        let controls = PlaybackControlsView.Model(store)

        #expect(currentTrack.metadata.title == song.title)
        #expect(currentTrack.metadata.artistName == song.artistName)
        #expect(currentTrack.artworkURL == song.artworkURL)
        #expect(timeline?.slider.value == 43)
        #expect(timeline?.slider.scale == .init(range: 0...215))
        #expect(timeline?.elapsedTimeText == "0:43")
        #expect(timeline?.durationText == "3:35")
        #expect(controls.primary.state == .pause)
        #expect(controls.primary.isEnabled)
    }

    @Test
    func currentTrackWithoutAnArtistUsesLocalizedPresentationFallback() {
        let track = Track(
            id: .init(providerID: .library, nativeID: "library"),
            title: "Library Track",
            artistName: nil,
            albumTitle: nil,
            artworkURL: nil,
            duration: 180
        )
        let model = PlaybackCurrentTrackView.Model(
            makePlaybackStore(song: track)
        )

        #expect(model.metadata.artistName == Locs.Common.unknownArtist)
    }

    @Test
    func pendingInitialReplacementShowsTargetTrackWhileLoading() {
        let song = makeTrack()
        let store = makePlaybackStore(
            song: nil,
            pendingTrack: song
        )

        let currentTrack = PlaybackCurrentTrackView.Model(store)
        let controls = PlaybackControlsView.Model(store)

        #expect(currentTrack.metadata.title == song.title)
        #expect(currentTrack.metadata.artistName == song.artistName)
        #expect(currentTrack.artworkURL == song.artworkURL)
        #expect(
            currentTrack.metadata.statusText == Locs.Playback.Status.loading
        )
        #expect(!controls.primary.isEnabled)
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
        let store = makePlaybackStore(
            song: confirmedTrack,
            status: .playing,
            pendingTrack: pendingTrack
        )

        let model = PlaybackCurrentTrackView.Model(store)

        #expect(model.metadata.title == confirmedTrack.title)
        #expect(model.metadata.artistName == confirmedTrack.artistName)
        #expect(model.artworkURL == confirmedTrack.artworkURL)
    }

    @Test
    func playbackFailureUsesInjectedPresentationStrings() {
        let track = makeTrack()
        let model = PlaybackCurrentTrackView.Model(
            makePlaybackStore(
                song: track,
                failureNotice: PlaybackFailureNotice(
                    trackID: track.id,
                    failure: .preparationFailed
                )
            ),
            strings: PlaybackCurrentTrackView.Model.Strings(
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
    func pendingSessionStatusPrecedesFailureNotice() {
        let track = makeTrack()
        let model = PlaybackCurrentTrackView.Model(
            makePlaybackStore(
                song: track,
                status: .playing,
                failureNotice: PlaybackFailureNotice(
                    trackID: track.id,
                    failure: .playbackFailed
                ),
                pendingStatusChange: .init(
                    requestID: UUID(0),
                    target: .paused
                )
            )
        )

        #expect(
            model.metadata.statusText == Locs.Playback.Status.paused
        )
    }

    @Test
    func activeTransitionPrecedesFailureNotice() {
        let confirmedTrack = makeTrack(nativeID: "confirmed")
        let pendingTrack = makeTrack(nativeID: "pending")
        let model = PlaybackCurrentTrackView.Model(
            makePlaybackStore(
                song: confirmedTrack,
                status: .playing,
                failureNotice: PlaybackFailureNotice(
                    trackID: confirmedTrack.id,
                    failure: .playbackFailed
                ),
                pendingTrack: pendingTrack
            )
        )

        #expect(model.metadata.title == confirmedTrack.title)
        #expect(
            model.metadata.statusText == Locs.Playback.Status.loading
        )
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
        #expect(model.tracks.map(\.durationText) == ["3:00", "3:00"])

        store.send(.queue(.currentTrackConfirmed(third.id)))
        let advancedModel = try #require(
            PlaybackUpNextView.Model(store, title: "Coming next")
        )

        #expect(advancedModel.tracks.map(\.id) == [second.id])
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
        let model = PlaybackCurrentTrackView.Model(
            makePlaybackStore(
                song: song,
                failureNotice: PlaybackFailureNotice(
                    trackID: song.id,
                    failure: failure
                )
            )
        )

        #expect(model.metadata.statusText == expectedText)
    }

    @Test
    func resourceUnavailableUsesProviderNeutralProductionCopy() {
        let song = makeTrack()
        let model = PlaybackCurrentTrackView.Model(
            makePlaybackStore(
                song: song,
                failureNotice: PlaybackFailureNotice(
                    trackID: song.id,
                    failure: .resourceUnavailable
                )
            )
        )

        #expect(
            model.metadata.statusText == "This track is currently unavailable."
        )
    }

    @Test
    func fullTimelineProjectsSliderControlsAndLocalizedLabels() throws {
        let song = makeTrack(duration: 215)
        let actions = LockIsolated<[PlaybackReducer.Action]>([])
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
        PlaybackTimelineReducer.Interaction.dragging(position: 60),
        .seeking(requestID: UUID(0), position: 60),
    ])
    func timelineInteractionOverridesConfirmedPosition(
        interaction: PlaybackTimelineReducer.Interaction
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
            .confirmedSnapshotReceived(
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
        #expect(timeline.slider.scale == .init(range: 0...120))
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
        let actions = LockIsolated<[PlaybackReducer.Action]>([])
        let store = makeActionRecordingStore(
            song: song,
            timelineDuration: 215,
            timelineIsSeekable: true,
            actions: actions
        )
        let controls = PlaybackControlsView.Model(store)
        let skipControls = PlaybackSkipControlsView.Model(store)
        let utilityControls = PlaybackUtilityControlsView.Model(store)

        controls.shuffle.perform()
        controls.previous.perform()
        controls.primary.perform()
        controls.next.perform()
        controls.repeatMode.perform()
        skipControls.controls[0].perform()
        skipControls.controls[1].perform()
        utilityControls.controls[0].perform()
        utilityControls.controls[1].perform()

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
        let store = makePlaybackStore(
            song: song,
            status: .playing,
            pendingStatusChange: .init(requestID: UUID(0), target: .paused)
        )
        let controls = PlaybackControlsView.Model(store)
        let utilityControls = PlaybackUtilityControlsView.Model(store)

        #expect(!controls.primary.isEnabled)
        #expect(!utilityControls.controls[1].isEnabled)

        let transitioningStore = makePlaybackStore(
            song: song,
            status: .playing,
            timelineDuration: 180,
            timelineIsSeekable: true,
            pendingTrack: song
        )
        let transitioningControls = PlaybackControlsView.Model(
            transitioningStore
        )
        let transitioningUtilityControls = PlaybackUtilityControlsView.Model(
            transitioningStore
        )
        #expect(!transitioningControls.primary.isEnabled)
        #expect(
            transitioningControls.primary.availability
                == .temporarilyBlocked
        )
        #expect(transitioningControls.next.availability == .disabled)
        #expect(
            transitioningUtilityControls.controls[0].availability
                == .temporarilyBlocked
        )
        #expect(transitioningUtilityControls.controls[1].isEnabled)

        let unconfirmedStore = makePlaybackStore(
            song: nil,
            status: .stopped,
            pendingTrack: song
        )
        let unconfirmedControls = PlaybackControlsView.Model(unconfirmedStore)
        let unconfirmedUtilityControls = PlaybackUtilityControlsView.Model(
            unconfirmedStore
        )
        #expect(!unconfirmedControls.primary.isEnabled)
        #expect(!unconfirmedUtilityControls.controls[1].isEnabled)
    }

    @Test
    func queueControlsProjectPermissionsLabelsAndSymbols() {
        let song = makeTrack()
        let queueTracks = [
            makeTrack(nativeID: "previous"),
            song,
            makeTrack(nativeID: "next"),
        ]
        let store = makePlaybackStore(song: song, queueTracks: queueTracks)
        let controls = PlaybackControlsView.Model(store)
        let utilityControls = PlaybackUtilityControlsView.Model(store)

        #expect(controls.previous.isEnabled)
        #expect(controls.next.isEnabled)
        #expect(controls.previous.systemImage == "backward.fill")
        #expect(controls.next.systemImage == "forward.fill")
        #expect(controls.primary.state == .play)
        #expect(
            controls.previous.accessibilityLabel == "Previous track"
        )
        #expect(controls.next.accessibilityLabel == "Next track")
        let utilityTitles = utilityControls.controls.map(\.title)
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
        confirmedPosition: TimeInterval = 0,
        timelineDuration: TimeInterval? = nil,
        timelineIsSeekable: Bool = false,
        timelineInteraction: PlaybackTimelineReducer.Interaction = .idle,
        repeatMode: PlaybackRepeatMode = .off,
        shuffleMode: PlaybackShuffleMode = .off,
        pendingTrack: Track? = nil,
        pendingStatusChange:
            PlaybackSessionReducer.PendingStatusChange? = nil,
        playbackOrder: [TrackID]? = nil
    ) -> StoreOf<PlaybackReducer> {
        let tracks = IdentifiedArray(
            uniqueElements: queueTracks ?? song.map { [$0] } ?? []
        )
        let pendingChanges = pendingTrack.map { pendingTrack in
            let pendingTracks = IdentifiedArray(
                uniqueElements: [pendingTrack]
            )
            return PlaybackQueueReducer.PendingChanges(
                active: .replacement(
                    makeConfirmedQueue(
                        pendingTracks,
                        startingAt: pendingTrack.id
                    )
                ),
                followUp: nil
            )
        }
        let confirmed = song.map {
            makeConfirmedQueue(
                tracks,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: playbackOrder ?? Array(tracks.ids)
                ),
                currentTrackID: $0.id,
                repeatMode: repeatMode,
                shuffleMode: shuffleMode
            )
        }
        return Store(
            initialState: PlaybackReducer.State(
                queue: PlaybackQueueReducer.State(
                    current: confirmed,
                    pendingChanges: pendingChanges
                ),
                timeline: PlaybackTimelineReducer.State(
                    confirmedPosition: confirmedPosition,
                    duration: timelineDuration,
                    isSeekable: timelineIsSeekable,
                    interaction: timelineInteraction
                ),
                session: PlaybackSessionReducer.State(
                    status: status,
                    pendingStatusChange: pendingStatusChange
                ),
                transition: pendingTrack.map {
                    PlaybackTransitionReducer.State(
                        phase: .starting(
                            .init(
                                target: $0,
                                baselineTrackID: song?.id
                            )
                        )
                    )
                },
                failureNotice: failureNotice,
                isPlayerPresented: false
            )
        ) {
            PlaybackReducer()
        }
    }

    private func makeActionRecordingStore(
        song: Track,
        timelineDuration: TimeInterval,
        timelineIsSeekable: Bool,
        actions: LockIsolated<[PlaybackReducer.Action]>
    ) -> StoreOf<PlaybackReducer> {
        let tracks = IdentifiedArray(uniqueElements: [song])
        return Store(
            initialState: PlaybackReducer.State(
                queue: .init(
                    current: makeConfirmedQueue(
                        tracks,
                        startingAt: song.id
                    )
                ),
                timeline: .init(
                    confirmedPosition: 43,
                    duration: timelineDuration,
                    isSeekable: timelineIsSeekable,
                    interaction: .idle
                ),
                session: .init(
                    status: .playing,
                    pendingStatusChange: nil
                ),
                transition: nil,
                failureNotice: nil,
                isPlayerPresented: false
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
    }

    private func makeConfirmedQueue(
        _ tracks: IdentifiedArrayOf<Track>,
        startingAt trackID: TrackID
    ) -> PlaybackQueue {
        guard
            let queue = PlaybackQueue(
                tracks: tracks,
                startingAt: trackID
            )
        else {
            preconditionFailure("Expected a valid playback queue fixture")
        }
        return queue
    }

    private func makeConfirmedQueue(
        _ tracks: IdentifiedArrayOf<Track>,
        playbackOrder: PlaybackQueueOrder,
        currentTrackID: TrackID,
        repeatMode: PlaybackRepeatMode,
        shuffleMode: PlaybackShuffleMode
    ) -> PlaybackQueue {
        guard
            let queue = PlaybackQueue(
                tracks: tracks,
                playbackOrder: playbackOrder,
                currentTrackID: currentTrackID,
                repeatMode: repeatMode,
                shuffleMode: shuffleMode
            )
        else {
            preconditionFailure("Expected a valid playback queue fixture")
        }
        return queue
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
