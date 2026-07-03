import ComposableArchitecture
import Foundation

@Reducer
struct FileFeature {
    @ObservableState
    struct State: Equatable {
        var item: FileItem
        var pendingUpload: ImportedMedia?
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
            case preview(URL, MediaKind)
        }
    }

    enum CancelID: String, Sendable { case transfer }

    @Dependency(\.mediaRemoteStorage) var mediaRemoteStorage

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .startUpload(media):
                state.pendingUpload = media
                state.item = state.item.with(status: .uploading(.pending(total: media.size)))
                return .send(.upload(media))

            case .tapped:
                switch state.item.status {
                case .remote:
                    state.item = state.item.with(status: .downloading(.pending(total: state.item.size)))
                    return .send(.download(state.item))
                case let .local(url):
                    return .send(.delegate(.preview(url, state.item.kind)))
                default:
                    return .none
                }

            case let .upload(media):
                return .run { send in
                    for try await event in mediaRemoteStorage.upload(media) {
                        switch event {
                        case let .progress(progress): await send(.progress(progress))
                        case let .finished(uploadedFile): await send(.uploadFinished(uploadedFile))
                        }
                    }
                } catch: { error, send in
                    await send(.failed(.upload(error)))
                }
                .cancellable(id: CancelID.transfer)

            case let .download(file):
                return .run { send in
                    for try await event in mediaRemoteStorage.download(file) {
                        switch event {
                        case let .progress(progress): await send(.progress(progress))
                        case let .finished(localURL): await send(.downloadFinished(localURL))
                        }
                    }
                } catch: { error, send in
                    await send(.failed(.download(error)))
                }
                .cancellable(id: CancelID.transfer)

            case let .progress(progress):
                switch state.item.status {
                case .uploading:
                    state.item = state.item.with(status: .uploading(progress))
                case .downloading:
                    state.item = state.item.with(status: .downloading(progress))
                default:
                    break
                }
                return .none

            case let .uploadFinished(file):
                state.item = file
                state.pendingUpload = nil
                return .none

            case let .downloadFinished(localURL):
                state.item = state.item.with(status: .local(localURL))
                return .none

            case let .failed(transferError):
                state.item = state.item.with(status: .failed(transferError))
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
                guard case let .failed(transferError) = state.item.status else { return .none }
                switch transferError.operation {
                case .upload:
                    guard let pendingUpload = state.pendingUpload else { return .none }
                    state.item = state.item.with(status: .uploading(.pending(total: pendingUpload.size)))
                    return .send(.upload(pendingUpload))
                case .download:
                    state.item = state.item.with(status: .downloading(.pending(total: state.item.size)))
                    return .send(.download(state.item))
                }

            case .delegate:
                return .none
            }
        }
    }
}
