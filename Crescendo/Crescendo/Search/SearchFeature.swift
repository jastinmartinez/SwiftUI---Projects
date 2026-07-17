import ComposableArchitecture
import Foundation

/// Owns catalog-search input and request state for resolved provider access.
@Reducer
struct SearchFeature {
    enum Phase: Equatable {
        case idle
        case loading(requestID: UUID)
        case loaded([SongSummary])
        case failed
    }

    @ObservableState
    struct State: Equatable {
        var query: String
        var phase: Phase
        var providerAccess: MusicProviderAccess?
    }

    /// Events emitted after search state validates a presentation action.
    enum Delegate: Equatable {
        case songSelected(SongSummary)
    }

    enum Action: Equatable {
        case queryChanged(String)
        case submitButtonTapped
        case retryButtonTapped
        case resultTapped(MusicItemID)
        case delegate(Delegate)
        case searchResponse(UUID, Result<[SongSummary], MusicProviderError>)
    }

    enum CancelID { case search }

    @Dependency(\.musicProvider) var musicProvider
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .queryChanged(let query):
                state.query = query
                state.phase = .idle
                return .cancel(id: CancelID.search)

            case .submitButtonTapped, .retryButtonTapped:
                let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard state.providerAccess?.authorization == .authorized,
                    !query.isEmpty
                else {
                    state.phase = .idle
                    return .cancel(id: CancelID.search)
                }
                let requestID = uuid()
                state.phase = .loading(requestID: requestID)
                return .run { send in
                    do {
                        let songs = try await musicProvider.search(query, 20)
                        await send(.searchResponse(requestID, .success(songs)))
                    } catch let error as MusicProviderError {
                        await send(.searchResponse(requestID, .failure(error)))
                    } catch {
                        await send(.searchResponse(requestID, .failure(.network)))
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case .resultTapped(let songID):
                guard case .loaded(let songs) = state.phase,
                    let song = songs.first(where: { $0.id == songID })
                else { return .none }
                return .send(.delegate(.songSelected(song)))

            case .delegate:
                return .none

            case .searchResponse(let requestID, .success(let songs)):
                let expectedPhase: Phase = .loading(requestID: requestID)
                guard state.phase == expectedPhase else { return .none }
                state.phase = .loaded(songs)
                return .none

            case .searchResponse(let requestID, .failure):
                let expectedPhase: Phase = .loading(requestID: requestID)
                guard state.phase == expectedPhase else { return .none }
                state.phase = .failed
                return .none
            }
        }
    }
}
