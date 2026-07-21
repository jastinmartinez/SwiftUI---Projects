import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackPresentationAdapterTests {
    @Test
    func playbackStatusMapsToLocalizedPresentation() {
        let cases: [(PlaybackFeature.Phase, String)] = [
            (.observing(.idle), Locs.Playback.Status.idle),
            (
                .observing(makeSnapshot(status: .playing, currentTime: 0)),
                Locs.Playback.Status.playing
            ),
            (
                .observing(makeSnapshot(status: .paused, currentTime: 0)),
                Locs.Playback.Status.paused
            ),
            (
                .observing(makeSnapshot(status: .stopped, currentTime: 0)),
                Locs.Playback.Status.stopped
            ),
            (.loading(.idle), Locs.Playback.Status.loading),
            (
                .failed(.playbackFailed, lastSnapshot: .idle),
                Locs.Playback.Status.failed
            ),
        ]

        for (phase, expectedStatusText) in cases {
            let store = makePlaybackStore(
                selectedSong: makeSong(),
                phase: phase,
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
            let model = PlaybackView.Model(store, providerName: nil)

            #expect(model.metadata.statusText == expectedStatusText)
        }
    }

    @Test
    func playbackPresentationMapsMetadataTimeAndChildModels() {
        let song = makeSong(duration: 215)
        let store = makePlaybackStore(
            selectedSong: song,
            phase: .observing(
                makeSnapshot(status: .playing, currentTime: 43)
            ),
            playbackEligibility: .eligible,
            capabilities: makeCapabilities(supportsSeeking: true)
        )
        let model = PlaybackView.Model(store, providerName: "Apple Music")
        let expectedRange: ClosedRange<TimeInterval> = 0...215

        #expect(model.metadata.title == song.title)
        #expect(model.metadata.artistName == song.artistName)
        #expect(model.metadata.providerAttribution?.contains("Apple Music") == true)
        #expect(model.artworkURL == song.artworkURL)
        #expect(model.timeline?.position == 43)
        #expect(model.timeline?.range == expectedRange)
        #expect(model.timeline?.elapsedTimeText == "0:43")
        #expect(model.timeline?.durationText == "3:35")
        #expect(model.controls.primaryAction == .pause)
        #expect(model.controls.isPrimaryEnabled)
        #expect(model.eligibility.presentation == .hidden)
    }

    @Test
    func timelineMapsLocalizedAccessibilityPresentation() throws {
        let store = makePlaybackStore(
            selectedSong: makeSong(duration: 215),
            phase: .observing(
                makeSnapshot(status: .playing, currentTime: 43)
            ),
            playbackEligibility: .eligible,
            capabilities: makeCapabilities(supportsSeeking: true)
        )

        let model = try #require(
            PlaybackView.Model(store, providerName: nil).timeline
        )

        #expect(model.strings.accessibilityLabel == Locs.Playback.position)
        #expect(model.strings.accessibilityValue == "0:43 of 3:35")
    }

    @Test
    func timelineFactoryUsesInjectedAccessibilityStrings() throws {
        let model = try #require(
            PlaybackTimelineView.Model.make(
                duration: 215,
                snapshot: makeSnapshot(status: .playing, currentTime: 43),
                timeline: PlaybackTimelineFeature.State(
                    interaction: .idle
                ),
                supportsSeeking: true,
                strings: { elapsedTime, durationTime in
                    PlaybackTimelineView.Model.Strings(
                        accessibilityLabel: "Custom position",
                        accessibilityValue: "\(elapsedTime) elapsed from \(durationTime)"
                    )
                },
                onPositionChanged: { _ in },
                onDragEnded: {}
            )
        )

        #expect(model.strings.accessibilityLabel == "Custom position")
        #expect(model.strings.accessibilityValue == "0:43 elapsed from 3:35")
    }

    @Test
    func unsupportedSeekingUsesFallbackAndOmitsTimeline() {
        let store = makePlaybackStore(
            selectedSong: makeSong(duration: 215),
            phase: .observing(.idle),
            playbackEligibility: .unknown,
            capabilities: makeCapabilities(supportsSeeking: false)
        )
        let model = PlaybackView.Model(store, providerName: nil)

        #expect(model.timeline == nil)
    }

    @Test
    func supportedSeekingWithoutPositiveDurationOmitsTimeline() {
        let durations: [TimeInterval?] = [nil, 0]

        for duration in durations {
            let store = makePlaybackStore(
                selectedSong: makeSong(duration: duration),
                phase: .observing(
                    makeSnapshot(status: .playing, currentTime: 43)
                ),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
            let model = PlaybackView.Model(store, providerName: nil)

            #expect(model.timeline == nil)
        }
    }

    @Test
    func timelineClampsPositionToSongDuration() {
        let cases: [(currentTime: TimeInterval, expectedPosition: TimeInterval)] = [
            (-1, 0),
            (216, 215),
        ]

        for testCase in cases {
            let store = makePlaybackStore(
                selectedSong: makeSong(duration: 215),
                phase: .observing(
                    makeSnapshot(
                        status: .playing,
                        currentTime: testCase.currentTime
                    )
                ),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
            let model = PlaybackView.Model(store, providerName: nil)

            #expect(model.timeline?.position == testCase.expectedPosition)
        }
    }

    @Test
    func playbackControlsMapPlayAvailability() {
        let unavailableModel = PlaybackControlsView.Model(
            makePlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .ineligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )
        let availableModel = PlaybackControlsView.Model(
            makePlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )
        let song = makeSong()
        let resumableModel = PlaybackControlsView.Model(
            makePlaybackStore(
                selectedSong: song,
                phase: .observing(
                    PlaybackSnapshot(
                        currentItemID: song.id,
                        status: .paused,
                        currentTime: 43,
                        playbackRate: .normal,
                        repeatMode: .off,
                        shuffleMode: .off
                    )
                ),
                playbackEligibility: .eligible,
                capabilities: makeResumeOnlyCapabilities()
            )
        )

        #expect(unavailableModel.primaryAction == .play)
        #expect(!unavailableModel.isPrimaryEnabled)
        #expect(availableModel.primaryAction == .play)
        #expect(availableModel.isPrimaryEnabled)
        #expect(resumableModel.primaryAction == .play)
        #expect(resumableModel.isPrimaryEnabled)
    }

    @Test
    func timelineCallbacksForwardReducerActions() {
        let actions = LockIsolated<[PlaybackFeature.Action]>([])
        let store: StoreOf<PlaybackFeature> = Store(
            initialState: PlaybackFeature.State(
                selectedSong: makeSong(duration: 215),
                queue: PlaybackQueueFeature.State(
                    songs: [],
                    currentItemID: nil
                ),
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true),
                timeline: PlaybackTimelineFeature.State(
                    interaction: .idle
                )
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
        let model = PlaybackView.Model(store, providerName: nil)

        model.timeline?.onPositionChanged(42)
        model.timeline?.onDragEnded()

        #expect(
            actions.value == [
                .timeline(.positionChanged(42)),
                .timeline(.dragEnded),
            ]
        )
    }

    @Test(arguments: [
        PlaybackTimelineFeature.Interaction.dragging(position: 86),
        .seeking(requestID: UUID(0), position: 86),
    ])
    func timelineInteractionPositionOverridesProviderSnapshot(
        interaction: PlaybackTimelineFeature.Interaction
    ) {
        let store = makePlaybackStore(
            selectedSong: makeSong(duration: 215),
            phase: .observing(
                makeSnapshot(status: .playing, currentTime: 43)
            ),
            playbackEligibility: .eligible,
            capabilities: makeCapabilities(supportsSeeking: true),
            timelineInteraction: interaction
        )

        let model = PlaybackView.Model(store, providerName: nil)

        #expect(model.timeline?.position == 86)
        #expect(model.timeline?.elapsedTimeText == "1:26")
    }

    @Test
    func sharedTimelineFactoryBuildsEqualModelsForCompactAndExpandedPlayers() throws {
        let duration: TimeInterval = 215
        let snapshot = makeSnapshot(status: .playing, currentTime: 43)
        let timelineState = PlaybackTimelineFeature.State(interaction: .idle)

        let compact = try #require(
            PlaybackTimelineView.Model.make(
                duration: duration,
                snapshot: snapshot,
                timeline: timelineState,
                supportsSeeking: true,
                strings: makeTimelineStrings(),
                onPositionChanged: { _ in },
                onDragEnded: {}
            )
        )
        let expanded = try #require(
            PlaybackTimelineView.Model.make(
                duration: duration,
                snapshot: snapshot,
                timeline: timelineState,
                supportsSeeking: true,
                strings: makeTimelineStrings(),
                onPositionChanged: { _ in },
                onDragEnded: {}
            )
        )

        #expect(compact.position == expanded.position)
        #expect(compact.range == expanded.range)
        #expect(compact.elapsedTimeText == expanded.elapsedTimeText)
        #expect(compact.durationText == expanded.durationText)
        #expect(compact.position == 43)
        #expect(compact.range == 0...215)
        #expect(compact.elapsedTimeText == "0:43")
        #expect(compact.durationText == "3:35")
    }

    @Test
    func sharedTimelineFactoryReturnsNilForUnsupportedOrInvalidDuration() {
        let snapshot = makeSnapshot(status: .playing, currentTime: 43)
        let timelineState = PlaybackTimelineFeature.State(interaction: .idle)

        let unsupportedSeeking = PlaybackTimelineView.Model.make(
            duration: 215,
            snapshot: snapshot,
            timeline: timelineState,
            supportsSeeking: false,
            strings: makeTimelineStrings(),
            onPositionChanged: { _ in },
            onDragEnded: {}
        )
        let missingDuration = PlaybackTimelineView.Model.make(
            duration: nil,
            snapshot: snapshot,
            timeline: timelineState,
            supportsSeeking: true,
            strings: makeTimelineStrings(),
            onPositionChanged: { _ in },
            onDragEnded: {}
        )
        let nonpositiveDuration = PlaybackTimelineView.Model.make(
            duration: 0,
            snapshot: snapshot,
            timeline: timelineState,
            supportsSeeking: true,
            strings: makeTimelineStrings(),
            onPositionChanged: { _ in },
            onDragEnded: {}
        )

        #expect(unsupportedSeeking == nil)
        #expect(missingDuration == nil)
        #expect(nonpositiveDuration == nil)
    }

    @Test
    func sharedTimelineFactoryForwardsCommittedActionValues() throws {
        let positions = LockIsolated<[TimeInterval]>([])
        let dragEndedCount = LockIsolated<Int>(0)

        let model = try #require(
            PlaybackTimelineView.Model.make(
                duration: 215,
                snapshot: makeSnapshot(status: .playing, currentTime: 43),
                timeline: PlaybackTimelineFeature.State(interaction: .idle),
                supportsSeeking: true,
                strings: makeTimelineStrings(),
                onPositionChanged: { position in
                    positions.withValue { $0.append(position) }
                },
                onDragEnded: {
                    dragEndedCount.withValue { $0 += 1 }
                }
            )
        )

        model.onPositionChanged(86)
        model.onDragEnded()

        #expect(positions.value == [86])
        #expect(dragEndedCount.value == 1)
    }

    @Test
    func playbackControlsForwardTransportActions() {
        let playingActions = LockIsolated<[PlaybackFeature.Action]>([])
        let playingStore = makeActionRecordingPlaybackStore(
            status: .playing,
            actions: playingActions
        )
        let playingModel = PlaybackControlsView.Model(playingStore)

        #expect(playingModel.primaryAction == .pause)
        #expect(playingModel.isStopEnabled)

        playingModel.onPrimaryAction()
        playingModel.onStop()

        #expect(playingActions.value == [.pauseTapped, .stopTapped])

        let pausedActions = LockIsolated<[PlaybackFeature.Action]>([])
        let pausedStore = makeActionRecordingPlaybackStore(
            status: .paused,
            actions: pausedActions
        )
        let pausedModel = PlaybackControlsView.Model(pausedStore)

        #expect(pausedModel.primaryAction == .play)
        #expect(pausedModel.isStopEnabled)

        pausedModel.onPrimaryAction()

        #expect(pausedActions.value == [.playTapped])
    }

    @Test
    func playerEligibilityMapsToPresentation() {
        let unknownModel = PlaybackEligibilityNoticeView.Model(
            makePlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )
        let ineligibleModel = PlaybackEligibilityNoticeView.Model(
            makePlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .ineligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )
        let eligibleModel = PlaybackEligibilityNoticeView.Model(
            makePlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )

        #expect(unknownModel.presentation == .availabilityUnknown)
        #expect(ineligibleModel.presentation == .subscriptionRequired)
        #expect(eligibleModel.presentation == .hidden)
    }

    @Test
    func playbackNowPlayingMapsSongAndOpensPlayer() {
        let song = makeSong(duration: 215)
        let store = makeAppStore(song: song, currentTime: 43)
        let model = PlaybackNowPlayingView.Model(store, song: song)

        #expect(model.title == song.title)
        #expect(model.artistName == song.artistName)
        #expect(model.artworkURL == song.artworkURL)
        #expect(model.isPlaying)
        #expect(model.timeline?.position == 43)
        #expect(model.timeline?.range == 0...215)
        #expect(model.timeline?.elapsedTimeText == "0:43")
        #expect(model.timeline?.durationText == "3:35")

        model.onOpenPlayer()

        #expect(store.isPlayerPresented)
    }

    @Test
    func unavailableFailureMapsToDistinctStatusText() {
        let store = makePlaybackStore(
            selectedSong: makeSong(),
            phase: .failed(.unavailable, lastSnapshot: .idle),
            playbackEligibility: .eligible,
            capabilities: .allEnabled
        )

        let model = PlaybackView.Model(store, providerName: nil)

        #expect(model.metadata.statusText == Locs.Playback.Status.unavailable)
        #expect(model.metadata.statusText != Locs.Playback.Status.failed)
    }

    @Test
    func providerNameMapsToAttributionText() throws {
        let store = makePlaybackStore(
            selectedSong: makeSong(),
            phase: .observing(makeSnapshot(status: .playing, currentTime: 0)),
            playbackEligibility: .eligible,
            capabilities: .allEnabled
        )

        let attributed = PlaybackView.Model(store, providerName: "Apple Music")
        let attribution = try #require(attributed.metadata.providerAttribution)
        #expect(attribution.contains("Apple Music"))

        let anonymous = PlaybackView.Model(store, providerName: nil)
        #expect(anonymous.metadata.providerAttribution == nil)
    }

    @Test
    func statusTextUsesExactApprovedWords() {
        let cases: [(PlaybackStatus, String)] = [
            (.playing, "Playing"),
            (.paused, "Paused"),
            (.stopped, "Stopped"),
        ]

        for (status, expectedWord) in cases {
            let store = makePlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(makeSnapshot(status: status, currentTime: 0)),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
            let model = PlaybackView.Model(store, providerName: nil)

            #expect(model.metadata.statusText == expectedWord)
        }
    }

    @Test
    func providerAttributionUsesExactApprovedCopy() {
        let store = makePlaybackStore(
            selectedSong: makeSong(),
            phase: .observing(makeSnapshot(status: .playing, currentTime: 0)),
            playbackEligibility: .eligible,
            capabilities: makeCapabilities(supportsSeeking: true)
        )

        let model = PlaybackView.Model(store, providerName: "Apple Music")

        #expect(model.metadata.providerAttribution == "Playing from Apple Music")
    }

    @Test
    func controlCommandWordsStayDistinctFromStatusWords() {
        #expect(Locs.Playback.play == "Play")
        #expect(Locs.Playback.pause == "Pause")
        #expect(Locs.Playback.stop == "Stop")

        #expect(Locs.Playback.play != Locs.Playback.Status.playing)
        #expect(Locs.Playback.pause != Locs.Playback.Status.paused)
        #expect(Locs.Playback.stop != Locs.Playback.Status.stopped)
    }

    // MARK: - Helpers

    private func makePlaybackStore(
        selectedSong: SongSummary?,
        phase: PlaybackFeature.Phase,
        playbackEligibility: CatalogPlaybackEligibility,
        capabilities: MusicProviderCapabilities,
        timelineInteraction: PlaybackTimelineFeature.Interaction = .idle
    ) -> StoreOf<PlaybackFeature> {
        Store(
            initialState: PlaybackFeature.State(
                selectedSong: selectedSong,
                queue: PlaybackQueueFeature.State(
                    songs: [],
                    currentItemID: nil
                ),
                phase: phase,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities,
                timeline: PlaybackTimelineFeature.State(
                    interaction: timelineInteraction
                )
            )
        ) {
            PlaybackFeature()
        }
    }

    private func makeActionRecordingPlaybackStore(
        status: PlaybackStatus,
        actions: LockIsolated<[PlaybackFeature.Action]>
    ) -> StoreOf<PlaybackFeature> {
        Store(
            initialState: PlaybackFeature.State(
                selectedSong: makeSong(duration: 215),
                queue: PlaybackQueueFeature.State(
                    songs: [],
                    currentItemID: nil
                ),
                phase: .observing(
                    makeSnapshot(status: status, currentTime: 43)
                ),
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: PlaybackTimelineFeature.State(
                    interaction: .idle
                )
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
    }

    private func makeAppStore(
        song: SongSummary,
        currentTime: TimeInterval = 0
    ) -> StoreOf<AppFeature> {
        Store(
            initialState: AppFeature.State(
                providerConnection: ProviderConnectionFeature.State(
                    providers: [.appleMusic],
                    connection: .connected(
                        providerID: .appleMusic,
                        access: MusicProviderAccess(
                            authorization: .authorized,
                            playbackEligibility: .eligible
                        )
                    )
                ),
                search: SearchFeature.State(
                    query: "",
                    status: .idle,
                    providerAccess: MusicProviderAccess(
                        authorization: .authorized,
                        playbackEligibility: .eligible
                    )
                ),
                playback: PlaybackFeature.State(
                    selectedSong: song,
                    queue: PlaybackQueueFeature.State(
                        songs: [],
                        currentItemID: nil
                    ),
                    phase: .observing(
                        makeSnapshot(status: .playing, currentTime: currentTime)
                    ),
                    playbackEligibility: .eligible,
                    capabilities: .allEnabled,
                    timeline: PlaybackTimelineFeature.State(
                        interaction: .idle
                    )
                ),
                isPlayerPresented: false,
                providerSwitch: nil,
                playbackCommand: nil
            )
        ) {
            AppFeature()
        }
    }

    private func makeSnapshot(
        status: PlaybackStatus,
        currentTime: TimeInterval
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            currentItemID: nil,
            status: status,
            currentTime: currentTime,
            playbackRate: .normal,
            repeatMode: .off,
            shuffleMode: .off
        )
    }

    private func makeCapabilities(
        supportsSeeking: Bool
    ) -> MusicProviderCapabilities {
        MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: supportsSeeking,
            supportsQueueReplacement: true
        )
    }

    private func makeResumeOnlyCapabilities() -> MusicProviderCapabilities {
        MusicProviderCapabilities(
            supportsCatalogSearch: true,
            supportsEmbeddedPlayback: true,
            supportsSeeking: true,
            supportsQueueReplacement: false
        )
    }

    private func makeTimelineStrings() -> (
        _ elapsedTime: String,
        _ durationTime: String
    ) -> PlaybackTimelineView.Model.Strings {
        { elapsedTime, durationTime in
            PlaybackTimelineView.Model.Strings(
                accessibilityLabel: "Position",
                accessibilityValue: "\(elapsedTime) of \(durationTime)"
            )
        }
    }

    private func makeSong(duration: TimeInterval? = nil) -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            duration: duration
        )
    }
}
