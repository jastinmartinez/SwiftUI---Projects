import Foundation

/// User-facing progress for upload and download transfers.
struct TransferProgress: Equatable {
    let bytesTransferred: Int64
    let totalBytes: Int64
    let completedChunks: Int
    let totalChunks: Int
}

extension TransferProgress {
    static func pending(total: Int64?) -> Self {
        let t = total ?? 0
        return .init(bytesTransferred: 0, totalBytes: t, completedChunks: 0, totalChunks: 0)
    }

    static func start(total: Int64?, chunkSize: Int) -> Self {
        let t = total ?? 0
        let chunks = t > 0 ? Int((t + Int64(chunkSize) - 1) / Int64(chunkSize)) : 0
        return .init(bytesTransferred: 0, totalBytes: t, completedChunks: 0, totalChunks: chunks)
    }
}
