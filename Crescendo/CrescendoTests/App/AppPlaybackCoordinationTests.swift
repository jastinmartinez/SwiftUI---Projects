import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func searchSelectionForwardsDirectlyToPlayback() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        let store = makeStore()

        await store.send(
            .search(
                .delegate(
                    .trackTapped(
                        tracks[1],
                        loadedResults: loadedResults
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    tracks[1].id,
                    loadedResults: loadedResults
                )
            )
        )
        await receiveTransitionStart(
            in: store,
            targetTrackID: tracks[1].id,
            loadedResults: loadedResults,
            baselineTrackID: nil,
            presentsPlayer: true
        )

        #expect(store.state.playback.queue.pendingTrack == tracks[1])
        #expect(store.state.playback.queue.current == nil)
    }

    @Test
    func laterSelectionStartsATransitionWithoutReopeningDismissedPlayer()
        async
    {
        let currentTracks = makeTracks(prefix: "current")
        let selectedTracks = makeTracks(prefix: "selected")
        let loadedResults = IdentifiedArray(uniqueElements: selectedTracks)
        let queue = makeQueue(
            tracks: currentTracks,
            currentTrackID: currentTracks[0].id
        )
        let store = makeStore(playbackQueue: queue)

        await store.send(
            .search(
                .delegate(
                    .trackTapped(
                        selectedTracks[0],
                        loadedResults: loadedResults
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    selectedTracks[0].id,
                    loadedResults: loadedResults
                )
            )
        )
        await receiveTransitionStart(
            in: store,
            targetTrackID: selectedTracks[0].id,
            loadedResults: loadedResults,
            baselineTrackID: currentTracks[0].id,
            presentsPlayer: false
        )

        #expect(!store.state.playback.isPlayerPresented)
        #expect(
            store.state.playback.queue.current?.currentTrack
                == currentTracks[0]
        )
        #expect(
            store.state.playback.queue.pendingTrack
                == selectedTracks[0]
        )
    }

    @Test
    func laterPaginatedResultsAreFrozenOnlyWhenLaterTrackIsTapped() async {
        let firstTracks = makeTracks(prefix: "first")
        let firstResults = IdentifiedArray(uniqueElements: firstTracks)
        let laterTrack = makeTrack(nativeID: "later")
        let loadedResults = IdentifiedArray(
            uniqueElements: firstTracks + [laterTrack]
        )
        let cursor = SearchCursor(value: "page-2")
        var state = makeState(
            playbackQueue: makeQueue(
                tracks: firstTracks,
                currentTrackID: firstTracks[0].id
            )
        )
        state.search.status = .loaded(
            SearchPaginationReducer.State(
                tracks: firstResults,
                nextCursor: cursor,
                status: .idle,
                providerID: providerID
            )
        )
        let store = makeStore(state: state) {
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    self.providerID: ProviderSearchClient(
                        searchPage: { request, limit in
                            #expect(request == .continuation(cursor))
                            #expect(limit == 20)
                            return SearchPage(
                                tracks: [laterTrack],
                                nextCursor: nil
                            )
                        }
                    )
                ]
            )
        }

        await store.send(.search(.pagination(.nextPageRequested)))
        await store.receive(
            .search(
                .pagination(
                    .continueSearch(
                        providerID: providerID,
                        cursor: cursor,
                        requestID: UUID(0)
                    )
                )
            )
        ) {
            guard case .loaded(var pagination) = $0.search.status else {
                return
            }
            pagination.status = .loading(requestID: UUID(0))
            $0.search.status = .loaded(pagination)
        }
        await store.receive(
            .search(
                .pagination(
                    .searchPageResponse(
                        UUID(0),
                        .success(
                            SearchPage(
                                tracks: [laterTrack],
                                nextCursor: nil
                            )
                        )
                    )
                )
            )
        ) {
            guard case .loaded(var pagination) = $0.search.status else {
                return
            }
            pagination.tracks.append(laterTrack)
            pagination.nextCursor = nil
            pagination.status = .idle
            $0.search.status = .loaded(pagination)
        }

        #expect(
            store.state.playback.queue.current?.tracks
                == firstResults
        )
        #expect(store.state.playback.queue.pendingTrack == nil)

        await store.send(.search(.resultTapped(laterTrack.id)))
        await store.receive(
            .search(
                .delegate(
                    .trackTapped(
                        laterTrack,
                        loadedResults: loadedResults
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    laterTrack.id,
                    loadedResults: loadedResults
                )
            )
        )
        await receiveTransitionStart(
            in: store,
            targetTrackID: laterTrack.id,
            loadedResults: loadedResults,
            baselineTrackID: firstTracks[0].id,
            presentsPlayer: false,
            requestID: UUID(1)
        )

        #expect(
            store.state.playback.queue.current?.tracks
                == firstResults
        )
        #expect(store.state.playback.queue.pendingTrack == laterTrack)
    }

    // MARK: - Helpers

    private let providerID = ProviderID(rawValue: "fake")

    private func receiveTransitionStart(
        in store: TestStoreOf<AppReducer>,
        targetTrackID: TrackID,
        loadedResults: IdentifiedArrayOf<Track>,
        baselineTrackID: TrackID?,
        presentsPlayer: Bool,
        requestID: UUID = UUID(0)
    ) async {
        await store.receive(
            .playback(
                .queue(
                    .selectionRequested(
                        targetTrackID,
                        loadedResults: loadedResults
                    )
                )
            )
        ) {
            $0.playback.queue.pendingChanges = .init(
                active: .replacement(
                    makeConfirmedQueue(
                        loadedResults,
                        startingAt: targetTrackID
                    )
                ),
                followUp: nil
            )
        }
        guard let target = loadedResults[id: targetTrackID] else {
            preconditionFailure("Expected target track in loaded results")
        }
        let intent = PlaybackTransitionReducer.Intent(
            target: target,
            baselineTrackID: baselineTrackID
        )
        await store.receive(
            .playback(
                .queue(
                    .delegate(.transitionRequested(targetTrackID))
                )
            )
        ) {
            $0.playback.transition = .init(phase: .starting(intent))
            $0.playback.failureNotice = nil
            $0.playback.isPlayerPresented = presentsPlayer
        }
        await store.receive(
            .playback(.session(.cancelPendingStatusChange))
        )
        await store.receive(.playback(.transition(.start))) {
            $0.playback.transition?.phase = .preparing(
                PlaybackTransitionReducer.Transaction(
                    requestID: requestID,
                    intent: intent
                ),
                .init(stage: .loading, latestTargetSnapshot: nil)
            )
        }
        await store.finish()
    }

    private func makeStore(
        state: AppReducer.State? = nil,
        playbackQueue: PlaybackQueueReducer.State = .init(
            current: nil
        ),
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<AppReducer> {
        TestStore(
            initialState: state
                ?? makeState(playbackQueue: playbackQueue)
        ) {
            AppReducer()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.playbackObservation.observations = { .finished }
            $0.playbackItem.load = { _, _, _ in
                throw CancellationError()
            }
            $0.playbackItem.rollback = { _ in }
            configureDependencies(&$0)
        }
    }

    private func makeState(
        playbackQueue: PlaybackQueueReducer.State = .init(
            current: nil
        )
    ) -> AppReducer.State {
        AppReducer.State(
            search: SearchReducer.State(
                query: "",
                status: .idle,
                providerID: providerID
            ),
            playback: PlaybackReducer.State(
                queue: playbackQueue,
                timeline: PlaybackTimelineReducer.State(
                    confirmedPosition: 0,
                    duration: nil,
                    isSeekable: false,
                    interaction: .idle
                ),
                session: PlaybackSessionReducer.State(
                    status: playbackQueue.current == nil
                        ? .idle
                        : .playing,
                    pendingStatusChange: nil
                ),
                transition: nil,
                failureNotice: nil,
                isPlayerPresented: false
            )
        )
    }

    private func makeQueue(
        tracks: [Track],
        currentTrackID: TrackID
    ) -> PlaybackQueueReducer.State {
        PlaybackQueueReducer.State(
            current: makeConfirmedQueue(
                IdentifiedArray(uniqueElements: tracks),
                startingAt: currentTrackID
            )
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

    private func makeTracks(prefix: String = "track") -> [Track] {
        [
            makeTrack(nativeID: "\(prefix)-1"),
            makeTrack(nativeID: "\(prefix)-2"),
            makeTrack(nativeID: "\(prefix)-3"),
        ]
    }

    private func makeTrack(nativeID: String) -> Track {
        Track(
            id: TrackID(providerID: providerID, nativeID: nativeID),
            title: nativeID,
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: 180
        )
    }
}
