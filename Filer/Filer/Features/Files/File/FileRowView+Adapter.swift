import ComposableArchitecture
import Foundation

extension FileRowView.Model {
    init(_ store: StoreOf<FileFeature>) {
        let item = store.item
        let sizeText = item.size?.formatted(.byteCount(style: .file))
        let kindName = switch item.kind {
        case .image: "Photo"
        case .video: "Video"
        }

        let subtitle: String = switch item.status {
        case .remote, .local:
            [sizeText, kindName].compactMap(\.self).joined(separator: " · ")
        case let .uploading(progress, _):
            "Uploading \(progress.bytesTransferred.formatted(.byteCount(style: .file))) / \(progress.totalBytes.formatted(.byteCount(style: .file)))"
        case .cancellingUpload:
            "Cancelling upload..."
        case let .downloading(progress):
            "Downloading \(progress.bytesTransferred.formatted(.byteCount(style: .file))) / \(progress.totalBytes.formatted(.byteCount(style: .file)))"
        case .failed:
            "Failed · Tap to retry"
        }

        let trailingOperation: TrailingOperation? = switch item.status {
        case .uploading, .downloading:
            TrailingOperation(kind: .cancel) { store.send(.cancelTapped) }
        case .failed:
            TrailingOperation(kind: .retry) { store.send(.retryTapped) }
        case .remote, .cancellingUpload, .local:
            nil
        }

        self.init(
            name: item.name,
            subtitle: subtitle,
            accessory: FileRowAccessoryView.Model(status: item.status),
            trailingOperation: trailingOperation,
            onTap: { store.send(.tapped) }
        )
    }
}
