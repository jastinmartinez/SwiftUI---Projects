import ComposableArchitecture
import Foundation

/// The root reducer responsible for application-wide state and coordination.
@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        let registeredProviders: [MusicProviderDescriptor]
        var activeProviderID: MusicProviderID?
        var search: SearchFeature.State
        var musicPlayback: MusicPlaybackFeature.State
        var isPlayerPresented: Bool
        var video: VideoPlaybackFeature.State?
        var videoCloseRequestID: UUID?
        var pendingProviderID: MusicProviderID?
        var providerSwitchRequestID: UUID?
        var playbackTransition: PlaybackTransition?

        var requiresProviderSelection: Bool {
            registeredProviders.count > 1 && activeProviderID == nil
        }

        init(
            registeredProviders: [MusicProviderDescriptor],
            activeProviderID: MusicProviderID?,
            search: SearchFeature.State,
            musicPlayback: MusicPlaybackFeature.State,
            isPlayerPresented: Bool,
            video: VideoPlaybackFeature.State?,
            videoCloseRequestID: UUID?,
            pendingProviderID: MusicProviderID?,
            providerSwitchRequestID: UUID?,
            playbackTransition: PlaybackTransition?
        ) {
            self.registeredProviders = registeredProviders
            self.activeProviderID = activeProviderID
            self.search = search
            self.musicPlayback = musicPlayback
            self.isPlayerPresented = isPlayerPresented
            self.video = video
            self.videoCloseRequestID = videoCloseRequestID
            self.pendingProviderID = pendingProviderID
            self.providerSwitchRequestID = providerSwitchRequestID
            self.playbackTransition = playbackTransition
        }
    }

    enum Action: Equatable {
        case task
        case providerSelected(MusicProviderID)
        case providerSwitchPauseSucceeded(
            requestID: UUID,
            providerID: MusicProviderID
        )
        case providerSwitchPauseFailed(
            requestID: UUID,
            providerID: MusicProviderID
        )
        case search(SearchFeature.Action)
        case musicPlayback(MusicPlaybackFeature.Action)
        case musicStartSucceeded(MusicItemID)
        case musicStartFailed(MusicItemID, MusicProviderError)
        case setPlayerPresented(Bool)
        case openVideoButtonTapped
        case openVideoSucceeded
        case openVideoFailed
        case closeVideoRequested
        case closeVideoFinished(UUID)
        case video(VideoPlaybackFeature.Action)
    }

    enum CancelID {
        case providerSwitch
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.musicProvider) var musicProvider
    @Dependency(\.videoPlayback) var videoPlayback

    var body: some ReducerOf<Self> {
        Scope(state: \.search, action: \.search) {
            SearchFeature()
        }
        Scope(state: \.musicPlayback, action: \.musicPlayback) {
            MusicPlaybackFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                if state.activeProviderID == nil, state.registeredProviders.count == 1 {
                    state.activeProviderID = state.registeredProviders[0].id
                }
                return .none

            case .providerSelected(let providerID):
                guard
                    state.registeredProviders.contains(
                        where: { $0.id == providerID }
                    ),
                    state.playbackTransition == nil,
                    state.videoCloseRequestID == nil
                else {
                    return .none
                }

                guard let activeProviderID = state.activeProviderID else {
                    state.activeProviderID = providerID
                    return .none
                }

                if providerID == activeProviderID {
                    guard
                        state.pendingProviderID != nil
                            || state.providerSwitchRequestID != nil
                    else {
                        return .none
                    }
                    state.pendingProviderID = nil
                    state.providerSwitchRequestID = nil
                    return .cancel(id: CancelID.providerSwitch)
                }

                if state.pendingProviderID == providerID,
                    state.providerSwitchRequestID != nil
                {
                    return .none
                }

                let requestID = uuid()
                state.pendingProviderID = providerID
                state.providerSwitchRequestID = requestID
                return .run { send in
                    do {
                        try await musicProvider.pause()
                        guard !Task.isCancelled else { return }
                        await send(
                            .providerSwitchPauseSucceeded(
                                requestID: requestID,
                                providerID: providerID
                            )
                        )
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .providerSwitchPauseFailed(
                                requestID: requestID,
                                providerID: providerID
                            )
                        )
                    }
                }
                .cancellable(id: CancelID.providerSwitch, cancelInFlight: true)

            case .providerSwitchPauseSucceeded(let requestID, let providerID):
                guard state.providerSwitchRequestID == requestID,
                    state.pendingProviderID == providerID,
                    let provider = state.registeredProviders.first(
                        where: { $0.id == providerID }
                    )
                else {
                    return .none
                }

                state.activeProviderID = providerID
                state.pendingProviderID = nil
                state.providerSwitchRequestID = nil
                state.search = SearchFeature.State(
                    query: "",
                    phase: .idle,
                    playbackEligibility: .unknown
                )
                state.musicPlayback = MusicPlaybackFeature.State(
                    selectedSong: nil,
                    phase: .observing(.idle),
                    playbackEligibility: .unknown,
                    capabilities: provider.capabilities
                )
                state.isPlayerPresented = false
                return .none

            case .providerSwitchPauseFailed(let requestID, let providerID):
                guard state.providerSwitchRequestID == requestID,
                    state.pendingProviderID == providerID
                else {
                    return .none
                }

                state.pendingProviderID = nil
                state.providerSwitchRequestID = nil
                return .none

            case .search(.delegate(.songSelected(let song))):
                state.musicPlayback.selectedSong = song
                state.musicPlayback.playbackEligibility = state.search.playbackEligibility
                state.isPlayerPresented = true
                return .none

            case .search:
                return .none

            case .musicPlayback(.delegate(.playRequested(let itemID))):
                guard state.playbackTransition == nil,
                    state.videoCloseRequestID == nil,
                    state.providerSwitchRequestID == nil
                else {
                    return .none
                }
                state.playbackTransition = .startingMusic(itemID)
                return .concatenate(
                    .send(.musicPlayback(.playbackStartAccepted)),
                    .run { send in
                        await videoPlayback.pause()
                        do {
                            try await musicProvider.play(itemID)
                            await send(.musicStartSucceeded(itemID))
                        } catch let error as MusicProviderError {
                            await send(.musicStartFailed(itemID, error))
                        } catch {
                            await send(.musicStartFailed(itemID, .playbackFailed))
                        }
                    }
                )

            case .musicPlayback:
                return .none

            case .musicStartSucceeded(let itemID):
                guard state.playbackTransition == .startingMusic(itemID) else {
                    return .none
                }
                state.playbackTransition = nil
                return .send(.musicPlayback(.transportFinished))

            case .musicStartFailed(let itemID, let error):
                guard state.playbackTransition == .startingMusic(itemID) else {
                    return .none
                }
                state.playbackTransition = nil
                return .send(.musicPlayback(.transportFailed(error)))

            case .setPlayerPresented(let isPresented):
                state.isPlayerPresented = isPresented
                return .none

            case .openVideoButtonTapped:
                guard state.video == nil,
                    state.videoCloseRequestID == nil,
                    state.playbackTransition == nil,
                    state.providerSwitchRequestID == nil
                else {
                    return .none
                }
                state.playbackTransition = .openingVideo
                return .run { send in
                    do {
                        try await musicProvider.pause()
                        await send(.openVideoSucceeded)
                    } catch {
                        await send(.openVideoFailed)
                    }
                }

            case .openVideoSucceeded:
                guard state.playbackTransition == .openingVideo else {
                    return .none
                }
                state.playbackTransition = nil
                state.video = VideoPlaybackFeature.State(
                    urlText: "",
                    loadedVideoURL: nil,
                    phase: .observing(.idle),
                    observationID: nil
                )
                return .none

            case .openVideoFailed:
                guard state.playbackTransition == .openingVideo else {
                    return .none
                }
                state.playbackTransition = nil
                return .none

            case .video(.delegate(.closeRequested)):
                return .send(.closeVideoRequested)

            case .closeVideoRequested:
                guard state.video != nil,
                    state.videoCloseRequestID == nil,
                    state.playbackTransition == nil,
                    state.providerSwitchRequestID == nil
                else {
                    return .none
                }
                let requestID = uuid()
                state.videoCloseRequestID = requestID
                return .concatenate(
                    .send(.video(.routeExited)),
                    .run { send in
                        await videoPlayback.pause()
                        await videoPlayback.clear()
                        await send(.closeVideoFinished(requestID))
                    }
                )

            case .closeVideoFinished(let requestID):
                guard state.videoCloseRequestID == requestID else {
                    return .none
                }
                state.video = nil
                state.videoCloseRequestID = nil
                return .none

            case .video:
                return .none
            }
        }
        .ifLet(\.video, action: \.video) {
            VideoPlaybackFeature()
        }
    }
}
