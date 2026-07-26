import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackNowPlayingPresentationTests {
    @Test
    func barToggleWhilePlayingPausesThroughReducer() async {
        let song = makeTrack(duration: nil)
        let (pauseCalled, pauseCalledContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackTransport.pause = { pauseCalledContinuation.yield() }
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)
        #expect(model.isPlaying)

        model.onTogglePlayPause()

        var pauseCalledIterator = pauseCalled.makeAsyncIterator()
        _ = await pauseCalledIterator.next()
    }

    @Test
    func barToggleProjectsPendingStatusChangePermission() {
        let song = makeTrack(duration: nil)
        var state = makeState(song: song, status: .playing)
        state.pendingStatusChange = PlaybackFeature.PendingStatusChange(
            requestID: UUID(0),
            target: .paused
        )
        let store = Store(initialState: state) {
            PlaybackFeature()
        }

        let model = PlaybackNowPlayingView.Model(store, song: song)

        #expect(!model.isPlayEnabled)
        #expect(!model.isPlaying)
    }

    @Test
    func barOpenRoutesPresentationThroughPlayback() {
        let song = makeTrack(duration: nil)
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackFeature()
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)

        model.onOpenPlayer()

        #expect(store.isPlayerPresented)
    }

    @Test
    func barToggleWhilePausedResumesWithoutResettingSelection() async {
        let song = makeTrack(duration: nil)
        let resolveCallCount = LockIsolated(0)
        let resumeCallCount = LockIsolated(0)
        let (resumeStarted, resumeStartedContinuation) = AsyncStream<Void>.makeStream()
        let (finishResume, finishResumeContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .paused)) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackResourceClients = ProviderClientRegistry(
                clients: [
                    "fake": PlaybackResourceClient(
                        resolve: { trackID in
                            resolveCallCount.withValue { $0 += 1 }
                            return PlaybackResource(
                                trackID: trackID,
                                location: .localFile(
                                    URL(fileURLWithPath: "/tmp/song.m4a")
                                )
                            )
                        }
                    )
                ]
            )
            $0.playbackTransport.play = {
                resumeCallCount.withValue { $0 += 1 }
                resumeStartedContinuation.yield()
                for await _ in finishResume { break }
            }
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)
        #expect(!model.isPlaying)

        model.onTogglePlayPause()

        var resumeStartedIterator = resumeStarted.makeAsyncIterator()
        _ = await resumeStartedIterator.next()
        #expect(store.queue.currentTrack == song)
        #expect(resolveCallCount.value == 0)
        #expect(resumeCallCount.value == 1)

        finishResumeContinuation.yield()
        finishResumeContinuation.finish()
        resumeStartedContinuation.finish()
    }

    @Test
    func compactTimelineUsesSharedSliderAndInjectedPrimaryLabel() throws {
        let song = makeTrack(duration: 180)
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackFeature()
        }
        let model = PlaybackNowPlayingView.Model(store, song: song)
        let timeline = try #require(model.timeline)

        #expect(timeline.slider.scale == .init(range: 0...180))
        #expect(model.playPauseAccessibilityLabel == Locs.Playback.pause)
    }

    // MARK: - Helpers

    private func makeState(
        song: Track,
        status: PlaybackStatus
    ) -> PlaybackFeature.State {
        let queue = IdentifiedArray(uniqueElements: [song])
        return PlaybackFeature.State(
            providerID: song.id.providerID,
            queue: PlaybackQueueFeature.State(
                tracks: queue,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(queue.ids)),
                currentTrackID: song.id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            status: status,
            failureNotice: nil,
            playbackEligibility: .eligible,
            capabilities: .allEnabled,
            timeline: PlaybackTimelineFeature.State(
                confirmedPosition: 0,
                interaction: .idle
            ),
            pendingPlaybackTransition: nil,
            pendingStatusChange: nil,
            pendingProviderReset: nil,
            isPlayerPresented: false
        )
    }

    private func makeTrack(duration: TimeInterval?) -> Track {
        Track(
            id: .init(providerID: "fake", nativeID: "1"),
            title: "Song",
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: duration
        )
    }
}
