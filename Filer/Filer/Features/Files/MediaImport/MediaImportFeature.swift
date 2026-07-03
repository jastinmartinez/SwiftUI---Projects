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
            case let .picked(selectedItems):
                guard !selectedItems.isEmpty else { return .none }
                state.phase = .loading
                return .run { send in
                    try await send(.loaded(mediaImport.load(selectedItems)))
                } catch: { error, send in
                    await send(.failed(error.localizedDescription))
                }
                .cancellable(id: CancelID.load)

            case let .loaded(loadedMediaItems):
                return .run { send in
                    try await mediaImportStore.removeExpired()
                    var importedMediaItems: [ImportedMedia] = []
                    for loadedMedia in loadedMediaItems {
                        try await importedMediaItems.append(mediaImportStore.store(loadedMedia))
                    }
                    await send(.cached(importedMediaItems))
                } catch: { error, send in
                    await send(.failed(error.localizedDescription))
                }
                .cancellable(id: CancelID.load)

            case let .cached(importedMediaItems):
                state.phase = .idle
                return .send(.delegate(.imported(importedMediaItems)))

            case let .failed(message):
                state.phase = .failed(message)
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
