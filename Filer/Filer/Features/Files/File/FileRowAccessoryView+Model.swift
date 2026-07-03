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
        case let .uploading(progress), let .downloading(progress):
            self = .progress(
                fraction: progress.totalBytes > 0 ? Double(progress.bytesTransferred) / Double(progress.totalBytes) : 0,
                label: "\(progress.completedChunks)/\(progress.totalChunks)"
            )
        case .local:
            self = .local
        case .failed:
            self = .failed
        }
    }
}
