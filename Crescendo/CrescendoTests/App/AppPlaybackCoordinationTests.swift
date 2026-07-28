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
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

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
        ) {
            $0.playback.isPlayerPresented = true
            $0.playback.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: loadedResults,
                targetTrackID: tracks[1].id
            )
        }
        await store.receive(
            .playback(
                .resolveTransition(
                    requestID: UUID(0),
                    trackID: tracks[1].id
                )
            )
        )
        await probe.waitUntilStarted()

        await store.send(.playback(.cancelPlaybackTransition)) {
            $0.playback.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func laterSelectionStartsATransitionWithoutReopeningDismissedPlayer() async {
        let currentSongs = makeTracks(prefix: "current")
        let currentQueue = IdentifiedArray(uniqueElements: currentSongs)
        let nextSongs = makeTracks(prefix: "next")
        let nextQueue = IdentifiedArray(uniqueElements: nextSongs)
        let probe = SuspendedOperationProbe<PlaybackResource>()
        let store = makeStore(
            playbackQueue: .init(
                tracks: currentQueue,
                playbackOrder: PlaybackQueueOrder(
                    trackIDs: Array(currentQueue.ids)
                ),
                currentTrackID: currentSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            ),
            isPlayerPresented: false
        ) {
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
        }

        await store.send(
            .search(
                .delegate(
                    .trackTapped(
                        nextSongs[0],
                        loadedResults: nextQueue
                    )
                )
            )
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    nextSongs[0].id,
                    loadedResults: nextQueue
                )
            )
        ) {
            $0.playback.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(0),
                queue: nextQueue,
                targetTrackID: nextSongs[0].id
            )
        }
        await store.receive(
            .playback(
                .resolveTransition(
                    requestID: UUID(0),
                    trackID: nextSongs[0].id
                )
            )
        )
        await probe.waitUntilStarted()

        #expect(!store.state.playback.isPlayerPresented)
        #expect(store.state.playback.queue.tracks == currentQueue)

        await store.send(.playback(.cancelPlaybackTransition)) {
            $0.playback.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    @Test
    func laterPaginatedResultsAreFrozenOnlyWhenLaterSongIsTapped() async {
        let firstPageSongs = makeTracks(prefix: "first")
        let firstPage = IdentifiedArray(uniqueElements: firstPageSongs)
        let laterSong = makeTrack(nativeID: "later")
        let laterSongs = firstPageSongs + [laterSong]
        let laterResults = IdentifiedArray(uniqueElements: laterSongs)
        let cursor = SearchCursor(value: "page-2")
        let probe = SuspendedOperationProbe<PlaybackResource>()
        var state = makeState(
            playbackQueue: PlaybackQueueFeature.State(
                tracks: firstPage,
                playbackOrder: PlaybackQueueOrder(trackIDs: Array(firstPage.ids)),
                currentTrackID: firstPageSongs[0].id,
                repeatMode: .off,
                shuffleMode: .off
            )
        )
        state.search.status = .loaded(
            SearchPaginationFeature.State(
                tracks: firstPage,
                nextCursor: cursor,
                status: .idle,
                providerID: providerID
            )
        )
        let store = makeStore(state: state) {
            $0.providerSearchClients = ProviderClientRegistry(
                clients: [
                    providerID: ProviderSearchClient(
                        searchPage: { request, limit in
                            #expect(request == .continuation(cursor))
                            #expect(limit == 20)
                            return SearchPage(
                                tracks: [laterSong],
                                nextCursor: nil
                            )
                        }
                    )
                ]
            )
            $0.playbackResourceClients = self.makeResourceClients { _ in
                try await probe.run()
            }
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
                            SearchPage(tracks: [laterSong], nextCursor: nil)
                        )
                    )
                )
            )
        ) {
            guard case .loaded(var pagination) = $0.search.status else {
                return
            }
            pagination.tracks.append(laterSong)
            pagination.nextCursor = nil
            pagination.status = .idle
            $0.search.status = .loaded(pagination)
        }

        #expect(store.state.playback.queue.tracks == firstPage)

        await store.send(.search(.resultTapped(laterSong.id)))
        await store.receive(
            .search(.delegate(.trackTapped(laterSong, loadedResults: laterResults)))
        )
        await store.receive(
            .playback(
                .selectionReceived(
                    laterSong.id,
                    loadedResults: laterResults
                )
            )
        ) {
            $0.playback.pendingPlaybackTransition = PendingPlaybackTransition(
                requestID: UUID(1),
                queue: laterResults,
                targetTrackID: laterSong.id
            )
        }
        await store.receive(
            .playback(
                .resolveTransition(
                    requestID: UUID(1),
                    trackID: laterSong.id
                )
            )
        )
        await probe.waitUntilStarted()

        #expect(store.state.playback.queue.tracks == firstPage)
        #expect(
            store.state.playback.pendingPlaybackTransition?.queue
                == laterResults
        )

        await store.send(.playback(.cancelPlaybackTransition)) {
            $0.playback.pendingPlaybackTransition = nil
        }
        await probe.waitUntilCancelled()
    }

    // MARK: - Helpers

    private let providerID = ProviderID(rawValue: "fake")

    private func makeStore(
        state: AppFeature.State? = nil,
        playbackQueue: PlaybackQueueFeature.State = .init(
            tracks: [],
            playbackOrder: PlaybackQueueOrder(trackIDs: []),
            currentTrackID: nil,
            repeatMode: .off,
            shuffleMode: .off
        ),
        isPlayerPresented: Bool = false,
        configureDependencies: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<AppFeature> {
        TestStore(
            initialState: state
                ?? makeState(
                    playbackQueue: playbackQueue,
                    isPlayerPresented: isPlayerPresented
                )
        ) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            configureDependencies(&$0)
        }
    }

    private func makeState(
        playbackQueue: PlaybackQueueFeature.State = .init(
            tracks: [],
            playbackOrder: PlaybackQueueOrder(trackIDs: []),
            currentTrackID: nil,
            repeatMode: .off,
            shuffleMode: .off
        ),
        isPlayerPresented: Bool = false
    ) -> AppFeature.State {
        AppFeature.State(
            search: SearchFeature.State(
                query: "",
                status: .idle,
                providerID: providerID
            ),
            playback: PlaybackFeature.State(
                queue: playbackQueue,
                status: playbackQueue.currentTrack == nil ? .idle : .playing,
                failureNotice: nil,
                timeline: PlaybackTimelineFeature.State(
                    confirmedPosition: 0,
                    duration: nil,
                    isSeekable: false,
                    interaction: .idle
                ),
                pendingPlaybackTransition: nil,
                pendingStatusChange: nil,
                isPlayerPresented: isPlayerPresented
            )
        )
    }

    private func makeResourceClients(
        resolve: @escaping @Sendable (TrackID) async throws -> PlaybackResource
    ) -> ProviderClientRegistry<PlaybackResourceClient> {
        ProviderClientRegistry(
            clients: [providerID: PlaybackResourceClient(resolve: resolve)]
        )
    }

    private func makeResource(for trackID: TrackID) -> PlaybackResource {
        PlaybackResource(
            trackID: trackID,
            location: .localFile(
                URL(fileURLWithPath: "/tmp/\(trackID.nativeID).m4a")
            )
        )
    }

    private func makeTracks(prefix: String = "song") -> [Track] {
        [
            makeTrack(nativeID: "\(prefix)-1"),
            makeTrack(nativeID: "\(prefix)-2"),
            makeTrack(nativeID: "\(prefix)-3"),
        ]
    }

    private func makeTrack(nativeID: String) -> Track {
        Track(
            id: .init(providerID: providerID, nativeID: nativeID),
            title: nativeID,
            artistName: "Artist",
            albumTitle: nil,
            artworkURL: nil,
            duration: 180
        )
    }
}
