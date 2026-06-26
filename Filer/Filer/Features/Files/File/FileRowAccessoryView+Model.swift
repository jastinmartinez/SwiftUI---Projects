import Foundation

extension FileRowAccessoryView {
    enum Model: Equatable {
        case remote
        case progress(fraction: Double, label: String)
        case local
        case failed
    }
}

extension FileRowAccessoryView.Model {
    init(status: FileItem.Status) {
        switch status {
        case .remote:
            self = .remote
        case let .uploading(p), let .downloading(p):
            self = .progress(
                fraction: p.totalBytes > 0 ? Double(p.bytesTransferred) / Double(p.totalBytes) : 0,
                label: "\(p.completedChunks)/\(p.totalChunks)"
            )
        case .local:
            self = .local
        case .failed:
            self = .failed
        }
    }
}
