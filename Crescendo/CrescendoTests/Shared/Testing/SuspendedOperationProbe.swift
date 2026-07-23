import ComposableArchitecture
import Foundation

/// Suspends one asynchronous test operation until explicitly completed or cancelled.
///
/// Each probe instance is single-use.
struct SuspendedOperationProbe<Output: Sendable>: Sendable {
    private let started: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private let cancelled: AsyncStream<Void>
    private let cancelledContinuation: AsyncStream<Void>.Continuation
    private let pendingContinuation =
        LockIsolated<CheckedContinuation<Output, any Error>?>(nil)
    private let cancellationObserved = LockIsolated(false)

    init() {
        (started, startedContinuation) = AsyncStream<Void>.makeStream()
        (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
    }

    var hasObservedCancellation: Bool {
        cancellationObserved.value
    }

    /// Signals that the operation started, then waits for completion or cancellation.
    func run() async throws -> Output {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingContinuation.withValue { $0 = continuation }
                startedContinuation.yield()
            }
        } onCancel: {
            pendingContinuation.withValue { continuation in
                continuation?.resume(throwing: CancellationError())
                continuation = nil
            }
            cancellationObserved.withValue { $0 = true }
            cancelledContinuation.yield()
        }
    }

    func waitUntilStarted() async {
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        startedContinuation.finish()
    }

    func waitUntilCancelled() async {
        var iterator = cancelled.makeAsyncIterator()
        _ = await iterator.next()
        cancelledContinuation.finish()
    }

    func succeed(with output: Output) {
        pendingContinuation.withValue { continuation in
            continuation?.resume(returning: output)
            continuation = nil
        }
    }

    func fail(with error: any Error) {
        pendingContinuation.withValue { continuation in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension SuspendedOperationProbe where Output == Void {
    func succeed() {
        succeed(with: ())
    }
}
