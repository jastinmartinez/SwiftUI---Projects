struct TransferError: Equatable {
    let operation: Operation // which action to retry
    let message: String
}

extension TransferError {
    enum Operation: Equatable { case upload, download }
}
