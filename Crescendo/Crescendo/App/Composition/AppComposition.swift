@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation

/// Constructs Crescendo's production root Store.
///
/// This is the application entry-point composition boundary. It selects live
/// runtime values, coordinates focused compositions, and exposes only the
/// fully configured Store. Reducers and views never depend on this type.
@MainActor
enum AppComposition {
    /// Constructs a new Store with Crescendo's production dependencies.
    static func makeStore() -> StoreOf<AppReducer> {
        let data:
            @Sendable (URLRequest) async throws -> (
                Data,
                URLResponse
            ) = { request in
                try await URLSession.shared.data(for: request)
            }
        let jamendoClientID =
            Bundle.main.object(forInfoDictionaryKey: "JamendoClientID")
            as? String
        let audiusAPIKey =
            Bundle.main.object(forInfoDictionaryKey: "AudiusAPIKey")
            as? String
        let library = LibraryComposition(
            applicationSupportURL: URL.applicationSupportDirectory
        )
        let providerSearch = ProviderSearchComposition(
            library: library.librarySearch,
            jamendo: ProviderSearchClient.live(
                jamendoClientID: jamendoClientID,
                data: data
            ),
            audius: ProviderSearchClient.live(
                audiusAPIKey: audiusAPIKey,
                data: data
            )
        )
        let playback = PlaybackComposition(
            player: AVPlayer(),
            preparer: .live(),
            data: data
        )

        return Store(
            initialState: AppReducer.State(
                searchProviderIDs: providerSearch.providerIDs
            )
        ) {
            AppReducer()
        } withDependencies: {
            $0.providerSearchClients = providerSearch.clients
            $0.playbackItem = playback.playbackItem
            $0.playbackTransport = playback.playbackTransport
            $0.playbackTimeline = playback.playbackTimeline
            $0.playbackObservation = playback.playbackObservation
            $0.playbackNowPlaying = playback.playbackNowPlaying
            $0.playbackShuffle = playback.playbackShuffle
            $0.libraryMediaStore = library.libraryMediaStore
            $0.audioMetadata = library.audioMetadata
            $0.libraryCatalog = library.libraryCatalog
        }
    }
}

private extension AppReducer.State {
    init(searchProviderIDs: [ProviderID]) {
        self.init(
            selectedTab: .search,
            search: SearchReducer.State(
                providerIDs: searchProviderIDs
            ),
            library: LibraryReducer.State(
                library: Library(items: []),
                catalog: .init(entries: []),
                loadStatus: .idle,
                path: [],
                isFileImporterPresented: false,
                recovery: nil,
                importBatch: nil,
                fileSelectionFailure: nil
            ),
            playback: PlaybackReducer.State(
                queue: PlaybackQueueReducer.State(current: nil),
                timeline: PlaybackTimelineReducer.State(
                    confirmedPosition: 0,
                    duration: nil,
                    isSeekable: false,
                    interaction: .idle
                ),
                session: PlaybackSessionReducer.State(
                    status: .idle,
                    pendingStatusChange: nil
                ),
                transition: nil,
                failureNotice: nil,
                isPlayerPresented: false
            )
        )
    }
}
