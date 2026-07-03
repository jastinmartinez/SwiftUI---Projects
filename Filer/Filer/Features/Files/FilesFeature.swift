import ComposableArchitecture
import Foundation

@Reducer
struct FilesFeature {
    @ObservableState
    struct State: Equatable {
        var files: IdentifiedArray<String, FileFeature.State> = IdentifiedArray(id: \.item.id)
        var importer = MediaImportFeature.State()
        var preview: PreviewItem?
        var loadPhase: LoadPhase = .loading
    }

    enum Action {
        case onAppear, previewDismissed
        case filesLoaded([FileItem]), loadFailed(String)
        case rows(IdentifiedAction<String, FileFeature.Action>)
        case importer(MediaImportFeature.Action)
    }

    @Dependency(\.mediaRemoteStorage) var mediaRemoteStorage

    var body: some Reducer<State, Action> {
        Scope(state: \.importer, action: \.importer) { MediaImportFeature() }
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    try await send(.filesLoaded(mediaRemoteStorage.list()))
                } catch: { error, send in
                    await send(.loadFailed(error.localizedDescription))
                }

            case let .filesLoaded(files):
                state.files = IdentifiedArray(
                    uniqueElements: files.map { FileFeature.State(item: $0) },
                    id: \.item.id
                )
                state.loadPhase = .ready
                return .none

            case let .loadFailed(message):
                state.loadPhase = .failed(message)
                return .none

            case let .importer(.delegate(.imported(importedMediaItems))):
                return .merge(importedMediaItems.map { importedMedia in
                    state.files.insert(FileFeature.State(item: FileItem(importing: importedMedia)), at: 0)
                    return .send(.rows(.element(id: importedMedia.id, action: .startUpload(importedMedia))))
                })

            case .importer:
                return .none

            case let .rows(.element(id, .delegate(.cancelled))):
                state.files.remove(id: id)
                return .none

            case let .rows(.element(_, .delegate(.preview(url, kind)))):
                state.preview = PreviewItem(url: url, kind: kind)
                return .none

            case .rows:
                return .none

            case .previewDismissed:
                state.preview = nil
                return .none
            }
        }
        .forEach(\.files, action: \.rows) { FileFeature() }
    }
}

extension FilesFeature.State {
    enum LoadPhase: Equatable { case loading, ready, failed(String) }
}

// MARK: - PreviewItem

extension FilesFeature {
    /// Sheet payload: the locally-cached file presented in the preview sheet.
    struct PreviewItem: Equatable, Identifiable {
        let url: URL
        let kind: MediaKind
        var id: URL { url }
    }
}
