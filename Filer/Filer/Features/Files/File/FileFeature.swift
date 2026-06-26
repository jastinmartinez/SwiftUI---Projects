import ComposableArchitecture
import Foundation

@Reducer
struct FileFeature {
    @ObservableState
    struct State: Equatable {
        var item: FileItem
        var source: ImportedMedia?
    }

    enum Action {
        case startUpload(ImportedMedia)
        case tapped, cancelTapped, retryTapped
        case upload(ImportedMedia)
        case download(FileItem)
        case progress(TransferProgress)
        case uploadFinished(FileItem)
        case downloadFinished(URL)
        case failed(TransferError)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case cancelled
            case preview(URL, FileItem.Kind)
        }
    }

    enum CancelID: String, Sendable { case transfer }

    @Dependency(\.storage) var storage

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .startUpload(media):
                state.source = media
                state.item = state.item.with(status: .uploading(.start(total: media.size)))
                return .send(.upload(media))

            case .tapped:
                switch state.item.status {
                case .remote:
                    state.item = state.item.with(status: .downloading(.start(total: state.item.size)))
                    return .send(.download(state.item))
                case let .local(url):
                    return .send(.delegate(.preview(url, state.item.kind)))
                default:
                    return .none
                }

            case let .upload(media):
                return .run { send in
                    for try await event in await storage.upload(media) {
                        switch event {
                        case let .progress(p): await send(.progress(p))
                        case let .finished(f): await send(.uploadFinished(f))
                        }
                    }
                } catch: { error, send in
                    await send(.failed(TransferError(operation: .upload, message: error.localizedDescription)))
                }
                .cancellable(id: CancelID.transfer)

            case let .download(file):
                return .run { send in
                    for try await event in await storage.download(file) {
                        switch event {
                        case let .progress(p): await send(.progress(p))
                        case let .finished(url): await send(.downloadFinished(url))
                        }
                    }
                } catch: { error, send in
                    await send(.failed(TransferError(operation: .download, message: error.localizedDescription)))
                }
                .cancellable(id: CancelID.transfer)

            case let .progress(p):
                switch state.item.status {
                case .uploading:
                    state.item = state.item.with(status: .uploading(p))
                case .downloading:
                    state.item = state.item.with(status: .downloading(p))
                default:
                    break
                }
                return .none

            case let .uploadFinished(file):
                state.item = file
                state.source = nil
                return .none

            case let .downloadFinished(url):
                state.item = state.item.with(status: .local(url))
                return .none

            case let .failed(e):
                state.item = state.item.with(status: .failed(e))
                return .none

            case .cancelTapped:
                switch state.item.status {
                case .uploading:
                    return .concatenate(
                        .cancel(id: CancelID.transfer),
                        .send(.delegate(.cancelled))
                    )
                case .downloading:
                    state.item = state.item.with(status: .remote)
                    return .cancel(id: CancelID.transfer)
                default:
                    return .none
                }

            case .retryTapped:
                guard case let .failed(e) = state.item.status else { return .none }
                switch e.operation {
                case .upload:
                    guard let m = state.source else { return .none }
                    state.item = state.item.with(status: .uploading(.start(total: m.size)))
                    return .send(.upload(m))
                case .download:
                    state.item = state.item.with(status: .downloading(.start(total: state.item.size)))
                    return .send(.download(state.item))
                }

            case .delegate:
                return .none
            }
        }
    }
}
