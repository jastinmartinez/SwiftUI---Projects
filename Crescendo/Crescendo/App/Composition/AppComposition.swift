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
    let initialState: AppFeature.State
    let providerAccessClients: ProviderClientRegistry<ProviderAccessClient>
    let providerSearchClients: ProviderClientRegistry<ProviderSearchClient>
    let playbackResourceClients: ProviderClientRegistry<PlaybackResourceClient>
    let playbackItem: PlaybackItemClient
    let playbackTransport: PlaybackTransportClient
    let playbackTimeline: PlaybackTimelineClient
    let playbackObservation: PlaybackObservationClient
    let playbackShuffle: PlaybackShuffleClient

    /// Assembles provider and playback implementations around one supplied player.
    ///
    /// Invalid Jamendo configuration leaves each Jamendo client registry empty
    /// while preserving the provider descriptor in initial application state.
    ///
    /// - Parameters:
    ///   - jamendoClientID: The generated bundle value used to validate Jamendo.
    ///   - player: The single player shared by the selected playback engine.
    ///   - preparer: The explicit AVPlayer resource-validation mechanism.
    ///   - data: The Jamendo HTTP transport.
    /// - Returns: Concrete initial state and dependency values for the root store.
    static func live(
        jamendoClientID: String?,
        player: AVPlayer,
        preparer: AVPlayerItemPreparer,
        data:
            @escaping @Sendable (URLRequest) async throws -> (
                Data,
                URLResponse
            )
    ) -> Self {
        var accessClientsByProvider: [ProviderID: ProviderAccessClient] = [:]
        var searchClientsByProvider: [ProviderID: ProviderSearchClient] = [:]
        var resourceClientsByProvider: [ProviderID: PlaybackResourceClient] = [:]

        if let jamendoConfiguration = JamendoConfiguration(
            clientID: jamendoClientID
        ) {
            let jamendoAPI = JamendoAPI(
                configuration: jamendoConfiguration,
                data: data
            )
            accessClientsByProvider[.jamendo] = .live(
                jamendo: jamendoConfiguration
            )
            searchClientsByProvider[.jamendo] = .live(jamendo: jamendoAPI)
            resourceClientsByProvider[.jamendo] = .live(jamendo: jamendoAPI)
        }

        let playbackEngine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: preparer
        )

        return Self(
            initialState: AppFeature.State(
                providerConnection: ProviderConnectionFeature.State(
                    providers: [.jamendo],
                    connection: .disconnected
                ),
                search: SearchFeature.State(
                    query: "",
                    status: .idle,
                    providerAccess: nil,
                    providerID: .jamendo
                ),
                playback: PlaybackFeature.State(
                    providerID: nil,
                    queue: PlaybackQueueFeature.State(
                        tracks: [],
                        playbackOrder: PlaybackQueueOrder(trackIDs: []),
                        currentTrackID: nil,
                        repeatMode: .off,
                        shuffleMode: .off
                    ),
                    status: .idle,
                    failureNotice: nil,
                    playbackEligibility: .unknown,
                    capabilities: .allEnabled,
                    timeline: PlaybackTimelineFeature.State(
                        confirmedPosition: 0,
                        duration: nil,
                        isSeekable: false,
                        interaction: .idle
                    ),
                    pendingPlaybackTransition: nil,
                    pendingStatusChange: nil,
                    pendingProviderReset: nil,
                    isPlayerPresented: false
                ),
                providerSwitch: nil
            ),
            providerAccessClients: ProviderClientRegistry(
                clients: accessClientsByProvider
            ),
            providerSearchClients: ProviderClientRegistry(
                clients: searchClientsByProvider
            ),
            playbackResourceClients: ProviderClientRegistry(
                clients: resourceClientsByProvider
            ),
            playbackItem: playbackEngine.item,
            playbackTransport: playbackEngine.transport,
            playbackTimeline: playbackEngine.timeline,
            playbackObservation: playbackEngine.observation,
            playbackShuffle: PlaybackShuffleClient(
                shuffle: { $0.shuffled() }
            )
        )
    }

    /// Builds the application store from the assembled state and dependencies.
    ///
    /// - Returns: The root application store.
    func store() -> StoreOf<AppFeature> {
        Store(initialState: initialState) {
            AppFeature()
        } withDependencies: {
            $0.providerAccessClients = providerAccessClients
            $0.providerSearchClients = providerSearchClients
            $0.playbackResourceClients = playbackResourceClients
            $0.playbackItem = playbackItem
            $0.playbackTransport = playbackTransport
            $0.playbackTimeline = playbackTimeline
            $0.playbackObservation = playbackObservation
            $0.playbackShuffle = playbackShuffle
        }
    }
}
