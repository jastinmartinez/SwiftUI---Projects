import ComposableArchitecture
import Foundation
import Testing

@testable import Crescendo

@MainActor
struct AppFeatureTests {
    @Test
    func taskLeavesSoleProviderDisconnected() async {
        let store = makeStore()

        await store.send(.task)

        #expect(store.state.providerConnection.connection == .disconnected)
        #expect(store.state.requiresProviderSelection)
    }

    @Test
    func providerSelectionRoutesConnectionThroughChild() async {
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let store = makeStore(currentAccess: { access })

        await store.send(.providerSelected(.appleMusic))
        await store.receive(.providerConnection(.connect(.appleMusic)))
        await store.receive(
            .providerConnection(.startConnection(.appleMusic))
        ) {
            $0.providerConnection.connection = .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: .appleMusic,
                        providerChanged: true
                    )
                )
            )
        )
        await store.receive(.resetProviderOwnedState(.appleMusic))
        await store.receive(.search(.cancelSearch))
        await store.receive(.playback(.timeline(.reset)))
        await store.receive(.replaceProviderOwnedState(.appleMusic))
        await store.receive(
            .providerConnection(
                .currentAccessResponse(
                    requestID: UUID(0),
                    providerID: .appleMusic,
                    access: access
                )
            )
        )
        await store.receive(
            .providerConnection(
                .accessResolved(
                    requestID: UUID(0),
                    providerID: .appleMusic,
                    access: access
                )
            )
        ) {
            $0.providerConnection.connection = .connected(
                providerID: .appleMusic,
                access: access
            )
        }
        await store.receive(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(
                            providerID: .appleMusic,
                            access: access
                        )
                    )
                )
            )
        ) {
            $0.search.providerAccess = access
        }
    }

    @Test
    func changedProviderConnectionStartResetsProviderOwnedState() async {
        let suspendedSeek = SuspendedSeekProbe()
        let song = makeSong()
        let futureProvider = makeProvider(id: "future")
        let state = makeState(
            providers: [.appleMusic, futureProvider],
            connection: .connecting(
                providerID: futureProvider.id,
                requestID: UUID(0)
            ),
            search: SearchFeature.State(
                query: "Selected song",
                status: loadedStatus(songs: [song]),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .eligible
                )
            ),
            playback: PlaybackFeature.State(
                selectedSong: song,
                phase: .observing(
                    PlaybackSnapshot(
                        currentItemID: song.id,
                        status: .playing,
                        currentTime: 42,
                        playbackRate: .normal,
                        repeatMode: .off,
                        shuffleMode: .off
                    )
                ),
                playbackEligibility: .eligible,
                capabilities: .allEnabled,
                timeline: PlaybackTimelineFeature.State(
                    interaction: .idle
                )
            ),
            isPlayerPresented: true
        )
        let store = makeStore(
            state: state,
            seek: suspendedSeek.callAsFunction
        )
        await startSuspendedSeek(suspendedSeek, on: store)

        await store.send(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: futureProvider.id,
                        providerChanged: true
                    )
                )
            )
        )
        await store.receive(.resetProviderOwnedState(futureProvider.id))
        await store.receive(.search(.cancelSearch)) {
            $0.search.status = .idle
        }
        await store.receive(.playback(.timeline(.reset))) {
            $0.playback.timeline.interaction = .idle
        }
        #expect(suspendedSeek.cancellationObserved.value)
        #expect(store.state.playback.selectedSong == song)

        await store.receive(.replaceProviderOwnedState(futureProvider.id)) {
            $0.search = SearchFeature.State(
                query: "",
                status: .idle,
                providerAccess: nil
            )
            $0.playback = PlaybackFeature.State(
                selectedSong: nil,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: futureProvider.musicCapabilities,
                timeline: PlaybackTimelineFeature.State(
                    interaction: .idle
                )
            )
            $0.isPlayerPresented = false
        }

        suspendedSeek.fail(with: .network)
        await store.finish()
        #expect(store.state.playback.timeline.interaction == .idle)
    }

    @Test
    func unchangedProviderConnectionStartPreservesProviderOwnedState() async {
        let state = makeState(
            connection: .connecting(
                providerID: .appleMusic,
                requestID: UUID(0)
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(
                    .connectionStarted(
                        providerID: .appleMusic,
                        providerChanged: false
                    )
                )
            )
        )

        #expect(store.state == state)
    }

    @Test
    func resolvedConnectionSynchronizesProviderAccess() async {
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .ineligible
        )
        let state = makeState(
            connection: .connected(
                providerID: .appleMusic,
                access: access
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(
                    .connectionResolved(
                        .connected(
                            providerID: .appleMusic,
                            access: access
                        )
                    )
                )
            )
        ) {
            $0.search.providerAccess = access
        }
    }

    @Test(arguments: [
        ProviderConnection.disconnected,
        .denied(providerID: .appleMusic),
        .restricted(providerID: .appleMusic),
        .failed(providerID: .appleMusic),
    ])
    func unavailableConnectionClearsProviderAccess(
        connection: ProviderConnection
    ) async {
        let staleAccess = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let state = makeState(
            connection: connection,
            search: SearchFeature.State(
                query: "result",
                status: loadedStatus(songs: [makeSong()]),
                providerAccess: staleAccess
            )
        )
        let store = makeStore(state: state)

        await store.send(
            .providerConnection(
                .delegate(.connectionResolved(connection))
            )
        ) {
            $0.search.providerAccess = nil
        }
    }

    @Test(arguments: [
        ProviderConnection.disconnected,
        .connecting(providerID: .appleMusic, requestID: UUID(0)),
        .denied(providerID: .appleMusic),
        .restricted(providerID: .appleMusic),
        .failed(providerID: .appleMusic),
        .connected(
            providerID: .appleMusic,
            access: MusicProviderAccess(
                authorization: .notDetermined,
                playbackEligibility: .eligible
            )
        ),
        .connected(
            providerID: .appleMusic,
            access: MusicProviderAccess(
                authorization: .denied,
                playbackEligibility: .eligible
            )
        ),
        .connected(
            providerID: .appleMusic,
            access: MusicProviderAccess(
                authorization: .restricted,
                playbackEligibility: .eligible
            )
        ),
    ])
    func unavailableProviderStateRejectsCompletedSearchSongTap(
        connection: ProviderConnection
    ) async {
        let song = makeSong()
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let state = makeState(
            connection: connection,
            search: SearchFeature.State(
                query: song.title,
                status: loadedStatus(songs: [song]),
                providerAccess: access
            )
        )
        let playedItemIDs = LockIsolated<[MusicItemID]>([])
        let store = makeStore(
            state: state,
            play: { itemID in
                playedItemIDs.withValue { $0.append(itemID) }
            }
        )

        await store.send(
            .search(
                .delegate(.songTapped(song, loadedResults: [song]))
            )
        )

        #expect(store.state == state)
        #expect(playedItemIDs.value.isEmpty)
    }

    @Test
    func authorizedIneligibleConnectionSelectsSongWithoutStartingTransport()
        async
    {
        let song = makeSong()
        let access = makeAccess(
            authorization: .authorized,
            playbackEligibility: .ineligible
        )
        let state = makeState(
            connection: .connected(
                providerID: .appleMusic,
                access: access
            ),
            search: SearchFeature.State(
                query: song.title,
                status: loadedStatus(songs: [song]),
                providerAccess: access
            )
        )
        let playedItemIDs = LockIsolated<[MusicItemID]>([])
        let store = makeStore(
            state: state,
            play: { itemID in
                playedItemIDs.withValue { $0.append(itemID) }
            }
        )

        await store.send(
            .search(
                .delegate(.songTapped(song, loadedResults: [song]))
            )
        ) {
            $0.isPlayerPresented = true
        }
        await store.receive(
            .playback(
                .songTapped(song, playbackEligibility: .ineligible)
            )
        )
        await store.receive(.playback(.timeline(.reset)))
        await store.receive(
            .playback(
                .applySongTap(song, playbackEligibility: .ineligible)
            )
        ) {
            $0.playback.selectedSong = song
            $0.playback.playbackEligibility = .ineligible
        }
        await store.receive(.playback(.requestPlayback))

        #expect(store.state.playbackCommand == nil)
        #expect(playedItemIDs.value.isEmpty)
    }

    @Test(arguments: [false, true])
    func selectedSongUsesConnectionPlaybackEligibilityWithoutChangingPresentation(
        isPlayerPresented: Bool
    ) async {
        let song = makeSong()
        let previousSong = makeSong(nativeID: "previous")
        let connectionAccess = makeAccess(
            authorization: .authorized,
            playbackEligibility: .eligible
        )
        let state = makeState(
            connection: .connected(
                providerID: .appleMusic,
                access: connectionAccess
            ),
            search: SearchFeature.State(
                query: "Selected song",
                status: loadedStatus(songs: [song]),
                providerAccess: makeAccess(
                    authorization: .authorized,
                    playbackEligibility: .ineligible
                )
            ),
            playback: PlaybackFeature.State(
                selectedSong: previousSong,
                phase: .observing(.idle),
                playbackEligibility: .unknown,
                capabilities: .allEnabled,
                timeline: PlaybackTimelineFeature.State(
                    interaction: .dragging(position: 18)
                )
            ),
            isPlayerPresented: isPlayerPresented
        )
        let store = makeStore(state: state)

        await store.send(
            .search(
                .delegate(.songTapped(song, loadedResults: [song]))
            )
        )
        await store.receive(
            .playback(
                .songTapped(song, playbackEligibility: .eligible)
            )
        )
        await store.receive(.playback(.timeline(.reset))) {
            $0.playback.timeline.interaction = .idle
        }
        await store.receive(
            .playback(
                .applySongTap(
                    song,
                    playbackEligibility: .eligible
                )
            )
        ) {
            $0.playback.selectedSong = song
            $0.playback.playbackEligibility = .eligible
        }
        await store.receive(.playback(.requestPlayback))
        await store.receive(
            .playback(.delegate(.playRequested(song.id)))
        ) {
            $0.playbackCommand = PlaybackCommandFeature.State(
                command: .play(song.id),
                requestID: UUID(0)
            )
        }
        await store.receive(\.playback.playbackCommandAccepted) {
            $0.playback.phase = .loading(.idle)
        }
        await store.receive(.playbackCommand(.start))
        await store.receive(
            .playbackCommand(
                .execute(.play(song.id), requestID: UUID(0))
            )
        )
        await store.receive(
            .playbackCommand(
                .response(
                    requestID: UUID(0),
                    result: .success(.play(song.id))
                )
            )
        )
        await store.receive(
            .playbackCommand(
                .delegate(
                    .completed(
                        requestID: UUID(0),
                        result: .success(.play(song.id))
                    )
                )
            )
        ) {
            $0.playbackCommand = nil
        }
        await store.receive(\.playback.transportFinished) {
            $0.playback.phase = .observing(.idle)
        }
    }

    @Test
    func unavailableProviderCannotBeSelected() async {
        let state = makeState(providers: [])
        let store = makeStore(state: state)

        await store.send(.providerSelected("missing"))

        #expect(store.state == state)
    }

    // MARK: - Helpers

    private func makeStore(
        state: AppFeature.State? = nil,
        currentAccess: @escaping @Sendable () async -> MusicProviderAccess = {
            MusicProviderAccess(
                authorization: .authorized,
                playbackEligibility: .unknown
            )
        },
        play: @escaping @Sendable (MusicItemID) async throws -> Void = { _ in },
        seek: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }
    ) -> TestStoreOf<AppFeature> {
        TestStore(initialState: state ?? makeState()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.providerAccess.currentAccess = currentAccess
            $0.playbackControl.play = play
            $0.playbackControl.seek = seek
        }
    }

    private func startSuspendedSeek(
        _ suspendedSeek: SuspendedSeekProbe,
        on store: TestStoreOf<AppFeature>
    ) async {
        await store.send(
            .playback(.timeline(.positionChanged(18)))
        ) {
            $0.playback.timeline.interaction = .dragging(position: 18)
        }
        await store.send(.playback(.timeline(.dragEnded))) {
            $0.playback.timeline.interaction = .seeking(
                requestID: UUID(0),
                position: 18
            )
        }
        await suspendedSeek.waitUntilStarted()
    }

    private func makeState(
        providers: [ProviderDescriptor] = [.appleMusic],
        connection: ProviderConnection = .disconnected,
        search: SearchFeature.State? = nil,
        playback: PlaybackFeature.State? = nil,
        isPlayerPresented: Bool = false
    ) -> AppFeature.State {
        AppFeature.State(
            providerConnection: ProviderConnectionFeature.State(
                providers: providers,
                connection: connection
            ),
            search: search
                ?? SearchFeature.State(
                    query: "",
                    status: .idle,
                    providerAccess: nil
                ),
            playback: playback
                ?? PlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: PlaybackTimelineFeature.State(
                        interaction: .idle
                    )
                ),
            isPlayerPresented: isPlayerPresented,
            providerSwitch: nil,
            playbackCommand: nil
        )
    }

    private func makeProvider(id: ProviderID) -> ProviderDescriptor {
        ProviderDescriptor(
            id: id,
            name: "Future",
            musicCapabilities: MusicProviderCapabilities(
                supportsCatalogSearch: true,
                supportsEmbeddedPlayback: true,
                supportsSeeking: false,
                supportsQueueReplacement: true
            )
        )
    }

    private func makeAccess(
        authorization: MusicAuthorizationStatus,
        playbackEligibility: CatalogPlaybackEligibility = .unknown
    ) -> MusicProviderAccess {
        MusicProviderAccess(
            authorization: authorization,
            playbackEligibility: playbackEligibility
        )
    }

    private func loadedStatus(songs: [SongSummary]) -> SearchFeature.Status {
        .loaded(
            SearchPaginationFeature.State(
                songs: .init(uniqueElements: songs),
                nextCursor: nil,
                status: .idle
            )
        )
    }

    private func makeSong(nativeID: String = "selected") -> SongSummary {
        SongSummary(
            id: .init(providerID: .appleMusic, nativeID: nativeID),
            title: "Selected song",
            artistName: "Artist",
            artworkURL: nil,
            duration: nil
        )
    }
}
