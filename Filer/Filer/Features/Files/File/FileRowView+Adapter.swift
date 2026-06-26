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
        case let .uploading(p):
            "Uploading \(p.bytesTransferred.formatted(.byteCount(style: .file))) / \(p.totalBytes.formatted(.byteCount(style: .file)))"
        case let .downloading(p):
            "Downloading \(p.bytesTransferred.formatted(.byteCount(style: .file))) / \(p.totalBytes.formatted(.byteCount(style: .file)))"
        case .failed:
            "Failed · Tap to retry"
        }

        self.init(
            name: item.name,
            subtitle: subtitle,
            accessory: FileRowAccessoryView.Model(status: item.status),
            send: { action in
                switch action {
                case .tapped: store.send(.tapped)
                case .cancelTapped: store.send(.cancelTapped)
                case .retryTapped: store.send(.retryTapped)
                }
            }
        )
    }
}
