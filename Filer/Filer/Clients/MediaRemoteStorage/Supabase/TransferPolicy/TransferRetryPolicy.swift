import Foundation

/// Retry limits shared by upload and download transfer engines.
struct TransferRetryPolicy: Equatable, Sendable {
    let maxRetries: Int
    let maxResumes: Int
    let maxRecreates: Int

    static let `default` = TransferRetryPolicy(
        maxRetries: 2,
        maxResumes: 3,
        maxRecreates: 1
    )

    func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code != .cancelled
    }
}
