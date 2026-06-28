import Foundation

/// Transfer limits shared by media remote upload and download transfer engines.
struct MediaRemoteTransferPolicy: Equatable, Sendable {
    let chunkSize: Int
    let maxRetries: Int
    let maxResumes: Int
    let maxRecreates: Int

    static let `default` = MediaRemoteTransferPolicy(
        chunkSize: 6 * 1024 * 1024,
        maxRetries: 2,
        maxResumes: 3,
        maxRecreates: 1
    )

    func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code != .cancelled
    }
}
