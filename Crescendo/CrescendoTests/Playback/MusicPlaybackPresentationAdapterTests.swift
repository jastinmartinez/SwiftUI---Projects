import ComposableArchitecture
import Testing

@testable import Crescendo

@MainActor
struct MusicPlaybackPresentationAdapterTests {
    @Test
    func playbackStatusMapsToLocalizedPresentation() {
        #expect(
            MusicPlaybackControlsView.Model.localizedStatus(for: .observing(.idle))
                == Locs.MusicPlayback.Status.idle
        )
        #expect(
            MusicPlaybackControlsView.Model.localizedStatus(
                for: .observing(makeSnapshot(status: .playing))
            ) == Locs.MusicPlayback.Status.playing
        )
        #expect(
            MusicPlaybackControlsView.Model.localizedStatus(
                for: .observing(makeSnapshot(status: .paused))
            ) == Locs.MusicPlayback.Status.paused
        )
        #expect(
            MusicPlaybackControlsView.Model.localizedStatus(
                for: .observing(makeSnapshot(status: .stopped))
            ) == Locs.MusicPlayback.Status.stopped
        )
        #expect(
            MusicPlaybackControlsView.Model.localizedStatus(for: .loading(.idle))
                == Locs.MusicPlayback.Status.loading
        )
        #expect(
            MusicPlaybackControlsView.Model.localizedStatus(
                for: .failed(.playbackFailed, lastSnapshot: .idle)
            ) == Locs.MusicPlayback.Status.failed
        )
    }

    @Test
    func playbackControlsMapPlayAvailability() {
        let unavailableModel = MusicPlaybackControlsView.Model(
            makeMusicPlaybackStore(playbackEligibility: .ineligible)
        )
        let availableModel = MusicPlaybackControlsView.Model(
            makeMusicPlaybackStore(playbackEligibility: .eligible)
        )

        #expect(!unavailableModel.canPlay)
        #expect(availableModel.canPlay)
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
            makeMusicPlaybackStore(playbackEligibility: .unknown)
        )
        let ineligibleModel = PlaybackEligibilityNoticeView.Model(
            makeMusicPlaybackStore(playbackEligibility: .ineligible)
        )
        let eligibleModel = PlaybackEligibilityNoticeView.Model(
            makeMusicPlaybackStore(playbackEligibility: .eligible)
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
        playbackEligibility: CatalogPlaybackEligibility
    ) -> StoreOf<MusicPlaybackFeature> {
        Store(
            initialState: MusicPlaybackFeature.State(
                selectedSong: makeSong(),
                phase: .observing(.idle),
                playbackEligibility: playbackEligibility,
                capabilities: .allEnabled
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
                    phase: .observing(makeSnapshot(status: .playing)),
                    playbackEligibility: .eligible,
                    capabilities: .allEnabled
                ),
                isPlayerPresented: false
            )
        ) {
            AppFeature()
        }
    }

    private func makeSnapshot(status: MusicPlaybackStatus) -> MusicPlaybackSnapshot {
        MusicPlaybackSnapshot(
            currentItem: nil,
            status: status,
            currentTime: 0
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
