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
            PlaybackReducer()
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
            PlaybackSessionReducer.PendingStatusChange(
                requestID: UUID(0),
                target: .paused
            )
        let store = Store(initialState: state) {
            PlaybackReducer()
        }

        let model = try #require(PlaybackNowPlayingView.Model(store))

        #expect(!model.isPlayPauseEnabled)
        #expect(!model.isPlaying)
    }

    @Test
    func barOpenRoutesPresentationThroughPlayback() throws {
        let song = makeTrack(duration: nil)
        let store = Store(initialState: makeState(song: song, status: .playing)) {
            PlaybackReducer()
        }
        let model = try #require(PlaybackNowPlayingView.Model(store))

        model.onOpenPlayer()

        #expect(store.isPlayerPresented)
    }

    @Test
    func barToggleWhilePausedResumesWithoutResettingSelection() async throws {
        let song = makeTrack(duration: nil)
        let resumeCallCount = LockIsolated(0)
        let (resumeStarted, resumeStartedContinuation) = AsyncStream<Void>.makeStream()
        let (finishResume, finishResumeContinuation) = AsyncStream<Void>.makeStream()
        let store = Store(initialState: makeState(song: song, status: .paused)) {
            PlaybackReducer()
        } withDependencies: {
            $0.uuid = .incrementing
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
        #expect(resumeCallCount.value == 1)

        finishResumeContinuation.yield()
        finishResumeContinuation.finish()
        resumeStartedContinuation.finish()
    }

    @Test
    func compactPlayerProjectsNextWithoutTimelineState() throws {
        let first = makeTrack(nativeID: "1", duration: 180)
        let second = makeTrack(nativeID: "2", duration: 200)
        let actions = LockIsolated<[PlaybackReducer.Action]>([])
        var state = makeState(song: first, status: .playing)
        state.queue.current = makeConfirmedQueue(
            IdentifiedArray(uniqueElements: [first, second]),
            startingAt: first.id
        )
        let store: StoreOf<PlaybackReducer> = Store(initialState: state) {
            Reduce { _, action in
                actions.withValue { $0.append(action) }
                return .none
            }
        }
        let model = try #require(PlaybackNowPlayingView.Model(store))

        #expect(model.playPauseAccessibilityLabel == Locs.Playback.pause)
        #expect(model.isNextEnabled)
        #expect(model.nextAccessibilityLabel == Locs.Playback.next)

        model.onNext()

        #expect(actions.value == [.nextTapped])
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
        state.transition = PlaybackTransitionReducer.State(
            phase: .starting(
                .init(
                    target: pendingTrack,
                    baselineTrackID: confirmedTrack.id
                )
            )
        )
        let store = Store(initialState: state) {
            PlaybackReducer()
        }

        let model = try #require(PlaybackNowPlayingView.Model(store))

        #expect(model.title == confirmedTrack.title)
        #expect(model.isPlaying)
        #expect(!model.isPlayPauseEnabled)
        #expect(model.playPauseAvailability == .temporarilyBlocked)
        #expect(model.nextAvailability == .disabled)
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
        state.transition = PlaybackTransitionReducer.State(
            phase: .starting(
                .init(
                    target: pendingTrack,
                    baselineTrackID: nil
                )
            )
        )
        let store = Store(initialState: state) {
            PlaybackReducer()
        }

        #expect(
            PlaybackNowPlayingView.Model(store).map { _ in true } == nil
        )
    }

    // MARK: - Helpers

    private func makeState(
        song: Track,
        status: PlaybackStatus
    ) -> PlaybackReducer.State {
        let queue = IdentifiedArray(uniqueElements: [song])
        return PlaybackReducer.State(
            queue: PlaybackQueueReducer.State(
                current: makeConfirmedQueue(
                    queue,
                    startingAt: song.id
                )
            ),
            timeline: PlaybackTimelineReducer.State(
                confirmedPosition: 0,
                duration: song.duration,
                isSeekable: true,
                interaction: .idle
            ),
            session: PlaybackSessionReducer.State(
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
