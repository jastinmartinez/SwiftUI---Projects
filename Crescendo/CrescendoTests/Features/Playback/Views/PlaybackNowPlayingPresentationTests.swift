import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct PlaybackNowPlayingPresentationTests {
    @Test
    func barToggleWhilePlayingPausesThroughReducer() async throws {
        let song = makeTrack(duration: nil)
        let (pauseCalled, pauseCalledContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackTransport.pause = { pauseCalledContinuation.yield() }
        }
        let model = try #require(PlaybackNowPlayingView.Model(store))
        #expect(model.isPlaying)

        model.onTogglePlayPause()

        var pauseCalledIterator = pauseCalled.makeAsyncIterator()
        _ = await pauseCalledIterator.next()
    }

    @Test
    func barToggleProjectsPendingStatusChangePermission() throws {
        let song = makeTrack(duration: nil)
        var state = makeState(song: song, status: .playing)
        state.session.pendingStatusChange =
            PlaybackSessionFeature.PendingStatusChange(
                requestID: UUID(0),
                target: .paused
            )
        let store = Store(initialState: state) {
            PlaybackFeature()
        }

        let model = try #require(PlaybackNowPlayingView.Model(store))

        #expect(!model.isPlayPauseEnabled)
        #expect(!model.isPlaying)
    }

    @Test
    func barOpenRoutesPresentationThroughPlayback() throws {
        let song = makeTrack(duration: nil)
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackFeature()
        }
        let model = try #require(PlaybackNowPlayingView.Model(store))

        model.onOpenPlayer()

        #expect(store.isPlayerPresented)
    }

    @Test
    func barToggleWhilePausedResumesWithoutResettingSelection() async throws {
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
        let model = try #require(PlaybackNowPlayingView.Model(store))
        #expect(!model.isPlaying)

        model.onTogglePlayPause()

        var resumeStartedIterator = resumeStarted.makeAsyncIterator()
        _ = await resumeStartedIterator.next()
        #expect(store.queue.current?.currentTrack == song)
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
        let model = try #require(PlaybackNowPlayingView.Model(store))
        let timeline = try #require(model.timeline)

        #expect(timeline.slider.scale == .init(range: 0...180))
        #expect(model.playPauseAccessibilityLabel == Locs.Playback.pause)
    }

    @Test
    func compactPlayerKeepsConfirmedTrackWhileAnotherTrackIsPending() throws {
        let confirmedTrack = makeTrack(
            nativeID: "confirmed",
            title: "Confirmed"
        )
        let pendingTrack = makeTrack(nativeID: "pending", title: "Pending")
        var state = makeState(song: confirmedTrack, status: .playing)
        let pendingTracks = IdentifiedArray(
            uniqueElements: [pendingTrack]
        )
        state.queue.pendingChanges = .init(
            active: .replacement(
                makeConfirmedQueue(
                    pendingTracks,
                    startingAt: pendingTrack.id
                )
            ),
            followUp: nil
        )
        state.transition = PlaybackTransitionFeature.State(
            phase: .starting(
                .init(
                    targetTrackID: pendingTrack.id,
                    baselineTrackID: confirmedTrack.id
                )
            )
        )
        let store = Store(initialState: state) {
            PlaybackFeature()
        }

        let model = try #require(PlaybackNowPlayingView.Model(store))

        #expect(model.title == confirmedTrack.title)
        #expect(model.isPlaying)
        #expect(!model.isPlayPauseEnabled)
    }

    @Test
    func compactPlayerRequiresAConfirmedTrack() {
        let pendingTrack = makeTrack(nativeID: "pending", title: "Pending")
        var state = makeState(song: pendingTrack, status: .idle)
        state.queue.current = nil
        let pendingTracks = IdentifiedArray(
            uniqueElements: [pendingTrack]
        )
        state.queue.pendingChanges = .init(
            active: .replacement(
                makeConfirmedQueue(
                    pendingTracks,
                    startingAt: pendingTrack.id
                )
            ),
            followUp: nil
        )
        state.transition = PlaybackTransitionFeature.State(
            phase: .starting(
                .init(
                    targetTrackID: pendingTrack.id,
                    baselineTrackID: nil
                )
            )
        )
        let store = Store(initialState: state) {
            PlaybackFeature()
        }

        #expect(
            PlaybackNowPlayingView.Model(store).map { _ in true } == nil
        )
    }

    // MARK: - Helpers

    private func makeState(
        song: Track,
        status: PlaybackStatus
    ) -> PlaybackFeature.State {
        let queue = IdentifiedArray(uniqueElements: [song])
        return PlaybackFeature.State(
            queue: PlaybackQueueFeature.State(
                current: makeConfirmedQueue(
                    queue,
                    startingAt: song.id
                )
            ),
            timeline: PlaybackTimelineFeature.State(
                confirmedPosition: 0,
                duration: song.duration,
                isSeekable: true,
                interaction: .idle
            ),
            session: PlaybackSessionFeature.State(
                status: status,
                pendingStatusChange: nil
            ),
            transition: nil,
            failureNotice: nil,
            isPlayerPresented: false
        )
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

    private func makeTrack(
        nativeID: String = "1",
        title: String = "Song",
        duration: TimeInterval? = nil
    ) -> Track {
        Track(
            id: .init(providerID: "fake", nativeID: nativeID),
            title: title,
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: duration
        )
    }
}
