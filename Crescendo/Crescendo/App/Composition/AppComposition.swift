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
    let providerSearchClients: ProviderClientRegistry<ProviderSearchClient>
    let playbackItem: PlaybackItemClient
    let playbackTransport: PlaybackTransportClient
    let playbackTimeline: PlaybackTimelineClient
    let playbackObservation: PlaybackObservationClient
    let playbackShuffle: PlaybackShuffleClient

    /// Assembles provider and playback implementations around one supplied player.
    ///
    /// Invalid Jamendo configuration leaves its search capability unregistered.
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
        var searchClientsByProvider: [ProviderID: ProviderSearchClient] = [:]

        if let jamendoConfiguration = JamendoConfiguration(
            clientID: jamendoClientID
        ) {
            let jamendoAPI = JamendoAPI(
                configuration: jamendoConfiguration,
                data: data
            )
            searchClientsByProvider[.jamendo] = .live(jamendo: jamendoAPI)
        }

        let playbackEngine = AVPlayerPlaybackEngine.live(
            player: player,
            preparer: preparer
        )

        return Self(
            initialState: AppFeature.State(
                search: SearchFeature.State(
                    query: "",
                    status: .idle,
                    providerID: .jamendo
                ),
                playback: PlaybackFeature.State(
                    queue: PlaybackQueueFeature.State(
                        current: nil
                    ),
                    timeline: PlaybackTimelineFeature.State(
                        confirmedPosition: 0,
                        duration: nil,
                        isSeekable: false,
                        interaction: .idle
                    ),
                    session: PlaybackSessionFeature.State(
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
            $0.providerSearchClients = providerSearchClients
            $0.playbackItem = playbackItem
            $0.playbackTransport = playbackTransport
            $0.playbackTimeline = playbackTimeline
            $0.playbackObservation = playbackObservation
            $0.playbackShuffle = playbackShuffle
        }
    }
}
