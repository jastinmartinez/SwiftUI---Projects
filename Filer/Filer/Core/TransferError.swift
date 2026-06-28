import Foundation

/// Reducer-facing transfer failure.
///
/// Transport clients keep their typed failures private to transfer policy. The
/// feature stores this lightweight value so retry can choose the original
/// operation and the UI can show a stable failure state.
struct TransferError: Equatable {
    let operation: Operation
    let message: String
}

extension TransferError {
    enum Operation: Equatable { case upload, download }

    static func upload(_ error: Error) -> TransferError {
        TransferError(operation: .upload, message: error.localizedDescription)
    }

    static func download(_ error: Error) -> TransferError {
        TransferError(operation: .download, message: error.localizedDescription)
    }
}
