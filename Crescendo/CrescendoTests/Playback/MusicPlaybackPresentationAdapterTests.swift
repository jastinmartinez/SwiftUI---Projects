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
            let model = MusicPlaybackView.Model(store)

            #expect(model.statusText == expectedStatusText)
        }
    }

    @Test
    func playbackPresentationMapsMetadataTimeAndChildModels() {
        let song = makeSong()
        let store = makeMusicPlaybackStore(
            selectedSong: song,
            phase: .observing(
                makeSnapshot(status: .playing, currentTime: 42)
            ),
            playbackEligibility: .ineligible,
            capabilities: makeCapabilities(supportsSeeking: true)
        )
        let model = MusicPlaybackView.Model(store)
        let expectedRange: ClosedRange<TimeInterval> = 0...102

        #expect(model.title == song.title)
        #expect(model.artistName == song.artistName)
        #expect(model.elapsedTimeText == "42")
        #expect(!model.controls.canPlay)
        #expect(model.eligibility.presentation == .subscriptionRequired)
        #expect(model.seek?.position == 42)
        #expect(model.seek?.range == expectedRange)
    }

    @Test
    func unavailablePresentationUsesFallbackAndOmitsSeeking() {
        let store = makeMusicPlaybackStore(
            selectedSong: nil,
            phase: .observing(.idle),
            playbackEligibility: .unknown,
            capabilities: makeCapabilities(supportsSeeking: false)
        )
        let model = MusicPlaybackView.Model(store)

        #expect(model.title == Locs.MusicPlayback.noSelection)
        #expect(model.artistName == nil)
        #expect(model.seek?.position == nil)
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

        #expect(!unavailableModel.canPlay)
        #expect(availableModel.canPlay)
    }

    @Test
    func seekCallbackForwardsReducerAction() {
        let actions = LockIsolated<[MusicPlaybackFeature.Action]>([])
        let store: StoreOf<MusicPlaybackFeature> = Store(
            initialState: MusicPlaybackFeature.State(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: makeCapabilities(supportsSeeking: true)
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
        let model = MusicPlaybackView.Model(store)

        model.seek?.onSeek(42)

        #expect(actions.value == [.seekRequested(42)])
    }

    @Test
    func playbackControlsForwardTransportActions() {
        let actions = LockIsolated<[MusicPlaybackFeature.Action]>([])
        let store: StoreOf<MusicPlaybackFeature> = Store(
            initialState: MusicPlaybackFeature.State(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: .eligible,
                capabilities: .allEnabled
            )
        ) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
        let model = MusicPlaybackControlsView.Model(store)

        model.onPlay()
        model.onPause()
        model.onStop()

        #expect(actions.value == [.playTapped, .pauseTapped, .stopTapped])
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
        let song = makeSong()
        let store = makeAppStore(song: song)
        let model = NowPlayingBarView.Model(store, song: song)

        #expect(model.title == song.title)
        #expect(model.artistName == song.artistName)
        #expect(model.isPlaying)

        model.onOpenPlayer()

        #expect(store.isPlayerPresented)
    }

    // MARK: - Helpers

    private func makeMusicPlaybackStore(
        selectedSong: SongSummary?,
        phase: MusicPlaybackFeature.Phase,
        playbackEligibility: CatalogPlaybackEligibility,
        capabilities: MusicProviderCapabilities
    ) -> StoreOf<MusicPlaybackFeature> {
        Store(
            initialState: MusicPlaybackFeature.State(
                selectedSong: selectedSong,
                phase: phase,
                playbackEligibility: playbackEligibility,
                capabilities: capabilities
            )
        ) {
            MusicPlaybackFeature()
        }
    }

    private func makeAppStore(song: SongSummary) -> StoreOf<AppFeature> {
        Store(
            initialState: AppFeature.State(
                registeredProviders: [.appleMusic],
                activeProviderID: "apple-music",
                search: SearchFeature.State(
                    query: "",
                    phase: .idle,
                    playbackEligibility: .eligible
                ),
                musicPlayback: MusicPlaybackFeature.State(
                    selectedSong: song,
                    phase: .observing(
                        makeSnapshot(status: .playing, currentTime: 0)
                    ),
                    playbackEligibility: .eligible,
                    capabilities: .allEnabled
                ),
                isPlayerPresented: false,
                video: nil,
                videoCloseRequestID: nil
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

    private func makeSong() -> SongSummary {
        SongSummary(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            artworkURL: nil
        )
    }
}
