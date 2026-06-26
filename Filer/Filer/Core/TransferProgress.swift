import Foundation

// chunk counts make "multipart" visible in the UI
struct TransferProgress: Equatable {
    let bytesTransferred: Int64
    let totalBytes: Int64
    let completedChunks: Int
    let totalChunks: Int
}

extension TransferProgress {
    static func start(total: Int64?, chunkSize: Int = 6 * 1024 * 1024) -> Self {
        let t = total ?? 0
        let chunks = t > 0 ? Int((t + Int64(chunkSize) - 1) / Int64(chunkSize)) : 0
        return .init(bytesTransferred: 0, totalBytes: t, completedChunks: 0, totalChunks: chunks)
    }
}
