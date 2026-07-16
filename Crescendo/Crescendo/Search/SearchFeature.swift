import ComposableArchitecture
import Foundation

/// Owns catalog-search input, mutually exclusive presentation state, and access checks.
@Reducer
struct SearchFeature {
    enum LoadingStage: Equatable {
        case checkingAccess
        case requestingAccess
        case searching
    }

    enum Status: Equatable {
        case idle
        case loading(requestID: UUID, stage: LoadingStage)
        case loaded([SongSummary])
        case denied
        case restricted
        case failed
    }

    @ObservableState
    struct State: Equatable {
        var query: String
        var status: Status
        var playbackEligibility: CatalogPlaybackEligibility
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
        case currentAccessResponse(UUID, MusicProviderAccess)
        case requestAccessResponse(UUID, MusicProviderAccess)
        case accessResolved(UUID, MusicProviderAccess)
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
                state.status = .idle
                return .cancel(id: CancelID.search)

            case .submitButtonTapped, .retryButtonTapped:
                let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    state.status = .idle
                    return .cancel(id: CancelID.search)
                }
                let requestID = uuid()
                state.status = .loading(requestID: requestID, stage: .checkingAccess)
                return .run { send in
                    let access = await musicProvider.currentAccess()
                    await send(.currentAccessResponse(requestID, access))
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case .resultTapped(let songID):
                guard case .loaded(let songs) = state.status,
                    let song = songs.first(where: { $0.id == songID })
                else { return .none }
                return .send(.delegate(.songSelected(song)))

            case .delegate:
                return .none

            case .currentAccessResponse(let requestID, let access):
                let expectedStatus: Status = .loading(
                    requestID: requestID,
                    stage: .checkingAccess
                )
                guard state.status == expectedStatus else { return .none }
                guard access.authorization == .notDetermined else {
                    return .send(.accessResolved(requestID, access))
                }
                state.status = .loading(requestID: requestID, stage: .requestingAccess)
                return .run { send in
                    let requestedAccess = await musicProvider.requestAccess()
                    await send(.requestAccessResponse(requestID, requestedAccess))
                }
                .cancellable(id: CancelID.search)

            case .requestAccessResponse(let requestID, let access):
                let expectedStatus: Status = .loading(
                    requestID: requestID,
                    stage: .requestingAccess
                )
                guard state.status == expectedStatus else { return .none }
                return .send(.accessResolved(requestID, access))

            case .accessResolved(let requestID, let access):
                guard case .loading(let activeRequestID, let stage) = state.status,
                    activeRequestID == requestID,
                    stage == .checkingAccess || stage == .requestingAccess
                else { return .none }
                state.playbackEligibility = access.playbackEligibility
                switch access.authorization {
                case .authorized:
                    let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.status = .loading(requestID: requestID, stage: .searching)
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
                    .cancellable(id: CancelID.search)
                case .denied:
                    state.status = .denied
                case .restricted:
                    state.status = .restricted
                case .notDetermined:
                    state.status = .failed
                }
                return .none

            case .searchResponse(let requestID, .success(let songs)):
                let expectedStatus: Status = .loading(
                    requestID: requestID,
                    stage: .searching
                )
                guard state.status == expectedStatus else { return .none }
                state.status = .loaded(songs)
                return .none

            case .searchResponse(let requestID, .failure):
                let expectedStatus: Status = .loading(
                    requestID: requestID,
                    stage: .searching
                )
                guard state.status == expectedStatus else { return .none }
                state.status = .failed
                return .none
            }
        }
    }
}
