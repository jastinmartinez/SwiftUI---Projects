import ComposableArchitecture
import PhotosUI
import SwiftUI

@Reducer
struct MediaImportFeature {
    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle

        enum Phase: Equatable {
            case idle, loading
            case failed(String)
        }
    }

    @CasePathable
    enum Action {
        case picked([PhotosPickerItem])
        case loaded([MediaImportClient.LoadedMedia])
        case cached([ImportedMedia])
        case failed(String)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable { case imported([ImportedMedia]) }
    }

    enum CancelID: String, Sendable { case load }

    @Dependency(\.mediaImport) var mediaImport
    @Dependency(\.mediaImportStore) var mediaImportStore

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .picked(items):
                guard !items.isEmpty else { return .none }
                state.phase = .loading
                return .run { send in
                    try await send(.loaded(mediaImport.load(items)))
                } catch: { e, send in
                    await send(.failed(e.localizedDescription))
                }
                .cancellable(id: CancelID.load)

            case let .loaded(loadedMedia):
                return .run { send in
                    try await mediaImportStore.removeExpired()
                    var cached: [ImportedMedia] = []
                    for media in loadedMedia {
                        try await cached.append(mediaImportStore.store(media))
                    }
                    await send(.cached(cached))
                } catch: { e, send in
                    await send(.failed(e.localizedDescription))
                }
                .cancellable(id: CancelID.load)

            case let .cached(medias):
                state.phase = .idle
                return .send(.delegate(.imported(medias)))

            case let .failed(m):
                state.phase = .failed(m)
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
