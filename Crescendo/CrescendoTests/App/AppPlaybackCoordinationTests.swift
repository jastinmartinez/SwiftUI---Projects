import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppPlaybackCoordinationTests {
    @Test
    func librarySelectionForwardsEmbeddedManagedURLDirectlyToPlayback() async {
        let playbackURL = URL(
            fileURLWithPath: "/managed/Library/library-track.m4a"
        )
        let track = Track(
            id: .init(providerID: .library, nativeID: "library-track"),
            title: "Library Track",
            artistName: "Library Artist",
            albumTitle: "Library Album",
            artworkURL: nil,
            duration: 180,
            playbackURL: playbackURL
        )
        let loadedTracks = IdentifiedArray(uniqueElements: [track])
        let store = makeStore {
            $0.libraryCatalog = LibraryCatalogClient(
                load: {
                    Issue.record("Library playback must not reload the catalog")
                    return .failure(.catalogReadFailed)
                },
                replace: { _ in
                    Issue.record("Library playback must not replace the catalog")
                    return .failure(.catalogWriteFailed)
                }
            )
        }

        await store.send(
            .library(
                .delegate(
                    .trackTapped(
                        track,
                        loadedTracks: loadedTracks
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    track.id,
                    loadedResults: loadedTracks
                )
            )
        )
        await receiveTransitionStart(
            in: store,
            targetTrackID: track.id,
            loadedResults: loadedTracks,
            baselineTrackID: nil,
            presentsPlayer: true
        )

        #expect(store.state.playback.queue.pendingTrack?.playbackURL == playbackURL)
    }

    @Test
    func railSelectionTransfersTheProviderFirstPageToPlayback() async {
        let tracks = makeTracks()
        let loadedResults = IdentifiedArray(uniqueElements: tracks)
        var state = makeState()
        state.search.providers[id: providerID]?.status = .loaded(
            ProviderSearchReducer.Page(
                tracks: loadedResults,
                nextCursor: SearchCursor(value: "page-2")
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .search(
                .providers(
                    .element(
                        id: providerID,
                        action: .resultTapped(tracks[1].id)
                    )
                )
            )
        )
        await store.receive(
            .search(
                .providers(
                    .element(
                        id: providerID,
                        action: .delegate(
                            .trackTapped(
                                tracks[1],
                                loadedTracks: loadedResults
                            )
                        )
                    )
                )
            )
        )
        await store.receive(
            .search(
                .delegate(
                    .trackTapped(
                        tracks[1],
                        loadedTracks: loadedResults
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
        #expect(
            pendingReplacement(in: store.state.playback.queue)?.tracks
                == loadedResults
        )
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
                        loadedTracks: loadedResults
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
    func destinationSelectionTransfersEveryLoadedTrackToPlayback() async {
        let firstTracks = makeTracks(prefix: "first")
        let laterTrack = makeTrack(nativeID: "later")
        let loadedResults = IdentifiedArray(
            uniqueElements: firstTracks + [laterTrack]
        )
        var state = makeState()
        state.search.destination = ProviderSearchResultsReducer.State(
            providerID: providerID,
            query: "track",
            tracks: loadedResults,
            nextCursor: nil,
            status: .idle
        )
        let store = makeStore(state: state)

        await store.send(
            .search(
                .destination(
                    .presented(.resultTapped(laterTrack.id))
                )
            )
        )
        await store.receive(
            .search(
                .destination(
                    .presented(
                        .delegate(
                            .trackTapped(
                                laterTrack,
                                loadedTracks: loadedResults
                            )
                        )
                    )
                )
            )
        )
        await store.receive(
            .search(
                .delegate(
                    .trackTapped(
                        laterTrack,
                        loadedTracks: loadedResults
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
            baselineTrackID: nil,
            presentsPlayer: true
        )

        #expect(
            pendingReplacement(in: store.state.playback.queue)?.tracks
                == loadedResults
        )
        #expect(store.state.playback.queue.pendingTrack == laterTrack)
    }

    @Test
    func destinationPaginationDoesNotMutateThePlaybackSnapshot() async {
        let firstTracks = makeTracks(prefix: "first")
        let firstResults = IdentifiedArray(uniqueElements: firstTracks)
        let laterTrack = makeTrack(nativeID: "later")
        let cursor = SearchCursor(value: "page-2")
        var state = makeState()
        state.search.destination = ProviderSearchResultsReducer.State(
            providerID: providerID,
            query: "track",
            tracks: firstResults,
            nextCursor: cursor,
            status: .idle
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

        await selectDestinationTrack(
            firstTracks[1],
            loadedResults: firstResults,
            in: store
        )
        let playbackBeforePagination = store.state.playback

        await store.send(
            .search(.destination(.presented(.nextPageRequested)))
        )
        await store.receive(
            .search(
                .destination(
                    .presented(
                        .continueSearch(
                            cursor,
                            requestID: UUID(1)
                        )
                    )
                )
            )
        ) {
            $0.search.destination?.status = .loading(
                requestID: UUID(1)
            )
        }
        await store.receive(
            .search(
                .destination(
                    .presented(
                        .searchPageResponse(
                            UUID(1),
                            .success(
                                SearchPage(
                                    tracks: [laterTrack],
                                    nextCursor: nil
                                )
                            )
                        )
                    )
                )
            )
        ) {
            $0.search.destination?.tracks.append(laterTrack)
            $0.search.destination?.nextCursor = nil
            $0.search.destination?.status = .idle
        }

        #expect(store.state.playback == playbackBeforePagination)
        #expect(
            pendingReplacement(in: store.state.playback.queue)?.tracks
                == firstResults
        )
    }

    @Test
    func dismissingResultsDoesNotClearThePlaybackTransition() async {
        let tracks = IdentifiedArray(uniqueElements: makeTracks())
        var state = makeState()
        state.search.destination = ProviderSearchResultsReducer.State(
            providerID: providerID,
            query: "track",
            tracks: tracks,
            nextCursor: nil,
            status: .idle
        )
        let store = makeStore(state: state)

        await selectDestinationTrack(
            tracks[1],
            loadedResults: tracks,
            in: store
        )
        let playbackBeforeDismissal = store.state.playback

        await store.send(.search(.destination(.dismiss))) {
            $0.search.destination = nil
        }

        #expect(store.state.playback == playbackBeforeDismissal)
        #expect(store.state.playback.transition != nil)
        #expect(
            pendingReplacement(in: store.state.playback.queue)?.tracks
                == tracks
        )
    }

    // MARK: - Helpers

    private let providerID = ProviderID(rawValue: "fake")

    private func selectDestinationTrack(
        _ track: Track,
        loadedResults: IdentifiedArrayOf<Track>,
        in store: TestStoreOf<AppReducer>
    ) async {
        await store.send(
            .search(
                .destination(
                    .presented(.resultTapped(track.id))
                )
            )
        )
        await store.receive(
            .search(
                .destination(
                    .presented(
                        .delegate(
                            .trackTapped(
                                track,
                                loadedTracks: loadedResults
                            )
                        )
                    )
                )
            )
        )
        await store.receive(
            .search(
                .delegate(
                    .trackTapped(
                        track,
                        loadedTracks: loadedResults
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    track.id,
                    loadedResults: loadedResults
                )
            )
        )
        await receiveTransitionStart(
            in: store,
            targetTrackID: track.id,
            loadedResults: loadedResults,
            baselineTrackID: nil,
            presentsPlayer: true
        )
    }

    private func pendingReplacement(
        in state: PlaybackQueueReducer.State
    ) -> PlaybackQueue? {
        guard
            let change = state.pendingChanges?.active,
            case .replacement(let queue) = change
        else {
            return nil
        }
        return queue
    }

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
            selectedTab: .search,
            search: SearchReducer.State(
                providerIDs: [providerID]
            ),
            library: makeLibraryState(),
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

    private func makeLibraryState() -> LibraryReducer.State {
        LibraryReducer.State(
            library: Library(items: []),
            catalog: .init(entries: []),
            loadStatus: .idle,
            path: [],
            isFileImporterPresented: false,
            recovery: nil,
            importBatch: nil,
            fileSelectionFailure: nil
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
