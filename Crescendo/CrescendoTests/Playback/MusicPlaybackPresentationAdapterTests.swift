import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct MusicPlaybackPresentationAdapterTests {
    @Test
    func playbackStatusMapsToLocalizedPresentation() {
        let cases: [(MusicPlaybackFeature.Phase, String)] = [
            (.observing(.idle), Locs.MusicPlayback.Status.idle),
            (
                .observing(makeSnapshot(status: .playing, currentTime: 0)),
                Locs.MusicPlayback.Status.playing
            ),
            (
                .observing(makeSnapshot(status: .paused, currentTime: 0)),
                Locs.MusicPlayback.Status.paused
            ),
            (
                .observing(makeSnapshot(status: .stopped, currentTime: 0)),
                Locs.MusicPlayback.Status.stopped
            ),
            (.loading(.idle), Locs.MusicPlayback.Status.loading),
            (
                .failed(.playbackFailed, lastSnapshot: .idle),
                Locs.MusicPlayback.Status.failed
            ),
        ]

        for (phase, expectedStatusText) in cases {
            let store = makeMusicPlaybackStore(
                selectedSong: makeSong(),
                phase: phase,
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
            let model = MusicPlaybackView.Model(store, providerName: nil)

            #expect(model.metadata.statusText == expectedStatusText)
        }
    }

    @Test
    func playbackPresentationMapsMetadataTimeAndChildModels() {
        let song = makeSong(duration: 215)
        let store = makeMusicPlaybackStore(
            selectedSong: song,
            phase: .observing(
                makeSnapshot(status: .playing, currentTime: 43)
            ),
            playbackEligibility: .eligible,
            capabilities: makeCapabilities(supportsSeeking: true)
        )
        let model = MusicPlaybackView.Model(store, providerName: "Apple Music")
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
        let store = makeMusicPlaybackStore(
            selectedSong: makeSong(duration: 215),
            phase: .observing(
                makeSnapshot(status: .playing, currentTime: 43)
            ),
            playbackEligibility: .eligible,
            capabilities: makeCapabilities(supportsSeeking: true)
        )

        let model = try #require(
            MusicPlaybackView.Model(store, providerName: nil).timeline
        )

        #expect(model.accessibilityLabel == Locs.MusicPlayback.position)
        #expect(model.accessibilityValue == "0:43 of 3:35")
    }

    @Test
    func unsupportedSeekingUsesFallbackAndOmitsTimeline() {
        let store = makeMusicPlaybackStore(
            selectedSong: makeSong(duration: 215),
            phase: .observing(.idle),
            playbackEligibility: .unknown,
            capabilities: makeCapabilities(supportsSeeking: false)
        )
        let model = MusicPlaybackView.Model(store, providerName: nil)

        #expect(model.timeline == nil)
    }

    @Test
    func supportedSeekingWithoutPositiveDurationOmitsTimeline() {
        let durations: [TimeInterval?] = [nil, 0]

        for duration in durations {
            let store = makeMusicPlaybackStore(
                selectedSong: makeSong(duration: duration),
                phase: .observing(
                    makeSnapshot(status: .playing, currentTime: 43)
                ),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
            let model = MusicPlaybackView.Model(store, providerName: nil)

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
            let store = makeMusicPlaybackStore(
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
            let model = MusicPlaybackView.Model(store, providerName: nil)

            #expect(model.timeline?.position == testCase.expectedPosition)
        }
    }

    @Test
    func playbackControlsMapPlayAvailability() {
        let unavailableModel = MusicPlaybackControlsView.Model(
            makeMusicPlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .ineligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )
        let availableModel = MusicPlaybackControlsView.Model(
            makeMusicPlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )
        let song = makeSong()
        let resumableModel = MusicPlaybackControlsView.Model(
            makeMusicPlaybackStore(
                selectedSong: song,
                phase: .observing(
                    MusicPlaybackSnapshot(
                        currentItem: song,
                        status: .paused,
                        currentTime: 43
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
        let actions = LockIsolated<[MusicPlaybackFeature.Action]>([])
        let store: StoreOf<MusicPlaybackFeature> = Store(
            initialState: MusicPlaybackFeature.State(
                selectedSong: makeSong(duration: 215),
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true),
                timeline: MusicPlaybackTimelineFeature.State(
                    interaction: .idle
                )
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
        let model = MusicPlaybackView.Model(store, providerName: nil)

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
        MusicPlaybackTimelineFeature.Interaction.dragging(position: 86),
        .seeking(requestID: UUID(0), position: 86),
    ])
    func timelineInteractionPositionOverridesProviderSnapshot(
        interaction: MusicPlaybackTimelineFeature.Interaction
    ) {
        let store = makeMusicPlaybackStore(
            selectedSong: makeSong(duration: 215),
            phase: .observing(
                makeSnapshot(status: .playing, currentTime: 43)
            ),
            playbackEligibility: .eligible,
            capabilities: makeCapabilities(supportsSeeking: true),
            timelineInteraction: interaction
        )

        let model = MusicPlaybackView.Model(store, providerName: nil)

        #expect(model.timeline?.position == 86)
        #expect(model.timeline?.elapsedTimeText == "1:26")
    }

    @Test
    func playbackControlsForwardTransportActions() {
        let playingActions = LockIsolated<[MusicPlaybackFeature.Action]>([])
        let playingStore = makeActionRecordingPlaybackStore(
            status: .playing,
            actions: playingActions
        )
        let playingModel = MusicPlaybackControlsView.Model(playingStore)

        #expect(playingModel.primaryAction == .pause)
        #expect(playingModel.isStopEnabled)

        playingModel.onPrimaryAction()
        playingModel.onStop()

        #expect(playingActions.value == [.pauseTapped, .stopTapped])

        let pausedActions = LockIsolated<[MusicPlaybackFeature.Action]>([])
        let pausedStore = makeActionRecordingPlaybackStore(
            status: .paused,
            actions: pausedActions
        )
        let pausedModel = MusicPlaybackControlsView.Model(pausedStore)

        #expect(pausedModel.primaryAction == .play)
        #expect(pausedModel.isStopEnabled)

        pausedModel.onPrimaryAction()

        #expect(pausedActions.value == [.playTapped])
    }

    @Test
    func playerEligibilityMapsToPresentation() {
        let unknownModel = PlaybackEligibilityNoticeView.Model(
            makeMusicPlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )
        let ineligibleModel = PlaybackEligibilityNoticeView.Model(
            makeMusicPlaybackStore(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .ineligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        )
        let eligibleModel = PlaybackEligibilityNoticeView.Model(
            makeMusicPlaybackStore(
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
    func nowPlayingBarMapsSongAndOpensPlayer() {
        let song = makeSong(duration: 215)
        let store = makeAppStore(song: song, currentTime: 43)
        let model = NowPlayingBarView.Model(store, song: song)

        #expect(model.title == song.title)
        #expect(model.artistName == song.artistName)
        #expect(model.artworkURL == song.artworkURL)
        #expect(model.isPlaying)
        #expect(model.elapsedTimeText == "0:43")
        #expect(model.durationText == "3:35")
        #expect(model.progress == 0.2)

        model.onOpenPlayer()

        #expect(store.isPlayerPresented)
    }

    @Test
    func unavailableFailureMapsToDistinctStatusText() {
        let store = makeMusicPlaybackStore(
            selectedSong: makeSong(),
            phase: .failed(.unavailable, lastSnapshot: .idle),
            playbackEligibility: .eligible,
            capabilities: .allEnabled
        )

        let model = MusicPlaybackView.Model(store, providerName: nil)

        #expect(model.metadata.statusText == Locs.MusicPlayback.Status.unavailable)
        #expect(model.metadata.statusText != Locs.MusicPlayback.Status.failed)
    }

    @Test
    func providerNameMapsToAttributionText() throws {
        let store = makeMusicPlaybackStore(
            selectedSong: makeSong(),
            phase: .observing(makeSnapshot(status: .playing, currentTime: 0)),
            playbackEligibility: .eligible,
            capabilities: .allEnabled
        )

        let attributed = MusicPlaybackView.Model(store, providerName: "Apple Music")
        let attribution = try #require(attributed.metadata.providerAttribution)
        #expect(attribution.contains("Apple Music"))

        let anonymous = MusicPlaybackView.Model(store, providerName: nil)
        #expect(anonymous.metadata.providerAttribution == nil)
    }

    // MARK: - Helpers

    private func makeMusicPlaybackStore(
        selectedSong: SongSummary?,
        phase: MusicPlaybackFeature.Phase,
        playbackEligibility: CatalogPlaybackEligibility,
        capabilities: MusicProviderCapabilities,
        timelineInteraction: MusicPlaybackTimelineFeature.Interaction = .idle
    ) -> StoreOf<MusicPlaybackFeature> {
        Store(
            initialState: MusicPlaybackFeature.State(
                selectedSong: selectedSong,
                phase: phase,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities,
                timeline: MusicPlaybackTimelineFeature.State(
                    interaction: timelineInteraction
                )
            )
        ) {
            MusicPlaybackFeature()
        }
    }

    private func makeActionRecordingPlaybackStore(
        status: MusicPlaybackStatus,
        actions: LockIsolated<[MusicPlaybackFeature.Action]>
    ) -> StoreOf<MusicPlaybackFeature> {
        Store(
            initialState: MusicPlaybackFeature.State(
                selectedSong: makeSong(duration: 215),
                phase: .observing(
                    makeSnapshot(status: status, currentTime: 43)
                ),
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: MusicPlaybackTimelineFeature.State(
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
                    phase: .idle,
                    providerAccess: MusicProviderAccess(
                        authorization: .authorized,
                        playbackEligibility: .eligible
                    )
                ),
                musicPlayback: MusicPlaybackFeature.State(
                    selectedSong: song,
                    phase: .observing(
                        makeSnapshot(status: .playing, currentTime: currentTime)
                    ),
                    playbackEligibility: .eligible,
                    capabilities: .allEnabled,
                    timeline: MusicPlaybackTimelineFeature.State(
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
        status: MusicPlaybackStatus,
        currentTime: TimeInterval
    ) -> MusicPlaybackSnapshot {
        MusicPlaybackSnapshot(
            currentItem: nil,
            status: status,
            currentTime: currentTime
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
