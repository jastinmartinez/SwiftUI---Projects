@preconcurrency import AVFoundation
import ComposableArchitecture
import Foundation

/// Holds the concrete values assembled by the application entry point.
///
/// This value exists only at the composition boundary. Reducers receive its
/// focused clients through TCA dependencies and never depend on the composition
/// value itself.
@MainActor
struct AppComposition {
    let initialState: AppReducer.State
    let providerSearchClients: ProviderClientRegistry<ProviderSearchClient>
    let playbackItem: PlaybackItemClient
    let playbackTransport: PlaybackTransportClient
    let playbackTimeline: PlaybackTimelineClient
    let playbackObservation: PlaybackObservationClient
    let playbackShuffle: PlaybackShuffleClient
    let libraryMediaStore: LibraryMediaStoreClient
    let audioMetadata: AudioMetadataClient
    let libraryCatalog: LibraryCatalogClient

    /// Assembles provider, Library, and playback implementations.
    ///
    /// Local search is always registered first. Each remote provider is
    /// registered only when its generated configuration value is valid.
    /// Invalid Jamendo or Audius configuration does not affect the other
    /// providers. All Library adapters and Local search share one managed
    /// filesystem rooted at
    /// `Application Support/Crescendo/Library`, while every typed catalog
    /// operation is serialized by one actor-backed store.
    ///
    /// - Parameters:
    ///   - jamendoClientID: The generated bundle value used to validate Jamendo.
    ///   - audiusAPIKey: The generated bundle value used to validate Audius.
    ///   - player: The single player shared by the selected playback engine.
    ///   - preparer: The explicit AVPlayer resource-validation mechanism.
    ///   - data: The HTTP transport shared by configured remote providers.
    ///   - applicationSupportURL: The system Application Support directory.
    /// - Returns: Concrete initial state and dependency values for the root store.
    static func live(
        jamendoClientID: String?,
        audiusAPIKey: String?,
        player: AVPlayer,
        preparer: AVPlayerItemPreparer,
        data:
            @escaping @Sendable (URLRequest) async throws -> (
                Data,
                URLResponse
            ),
        applicationSupportURL: URL
    ) -> Self {
        let playbackEngine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: preparer
        )
        let crescendoSupportURL = applicationSupportURL.appending(
            path: "Crescendo"
        )
        let libraryRootURL = crescendoSupportURL.appending(path: "Library")
        let libraryFileSystem = ManagedLibraryFileSystem(
            rootURL: libraryRootURL
        )
        let securityScopedFileCopy = SecurityScopedFileCopyClient.live(
            fileSystem: libraryFileSystem
        )
        let libraryMediaStore = LibraryMediaStoreClient.live(
            fileSystem: libraryFileSystem,
            securityScopedFileCopy: securityScopedFileCopy
        )
        let libraryCatalogStore = LibraryCatalogStore(
            catalogURL: libraryFileSystem.catalogURL,
            catalogFile: LibraryCatalogFileClient.live(
                fileSystem: libraryFileSystem
            )
        )
        let libraryCatalog = LibraryCatalogClient.live(
            store: libraryCatalogStore
        )
        var searchProviderIDs: [ProviderID] = [.library]
        var searchClientsByProvider: [ProviderID: ProviderSearchClient] = [
            .library: .live(
                libraryCatalog: libraryCatalog,
                libraryMediaStore: libraryMediaStore
            )
        ]

        if let jamendoConfiguration = JamendoConfiguration(
            clientID: jamendoClientID
        ) {
            let jamendoAPI = JamendoAPI(
                configuration: jamendoConfiguration,
                data: data
            )
            searchProviderIDs.append(.jamendo)
            searchClientsByProvider[.jamendo] = .live(jamendo: jamendoAPI)
        }

        if let audiusConfiguration = AudiusConfiguration(apiKey: audiusAPIKey) {
            let audiusAPI = AudiusAPI(
                configuration: audiusConfiguration,
                data: data
            )
            searchProviderIDs.append(.audius)
            searchClientsByProvider[.audius] = .live(audius: audiusAPI)
        }

        return Self(
            initialState: AppReducer.State(
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
                    queue: PlaybackQueueReducer.State(
                        current: nil
                    ),
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
            ),
            providerSearchClients: ProviderClientRegistry(
                clients: searchClientsByProvider
            ),
            playbackItem: playbackEngine.item,
            playbackTransport: playbackEngine.transport,
            playbackTimeline: playbackEngine.timeline,
            playbackObservation: playbackEngine.observation,
            playbackShuffle: PlaybackShuffleClient(
                shuffle: { $0.shuffled() }
            ),
            libraryMediaStore: libraryMediaStore,
            audioMetadata: .live(),
            libraryCatalog: libraryCatalog
        )
    }

    /// Builds the application store from the assembled state and dependencies.
    ///
    /// - Returns: The root application store.
    func store() -> StoreOf<AppReducer> {
        Store(initialState: initialState) {
            AppReducer()
        } withDependencies: {
            $0.providerSearchClients = providerSearchClients
            $0.playbackItem = playbackItem
            $0.playbackTransport = playbackTransport
            $0.playbackTimeline = playbackTimeline
            $0.playbackObservation = playbackObservation
            $0.playbackShuffle = playbackShuffle
            $0.libraryMediaStore = libraryMediaStore
            $0.audioMetadata = audioMetadata
            $0.libraryCatalog = libraryCatalog
        }
    }
}
