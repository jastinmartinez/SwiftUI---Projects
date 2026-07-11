import Foundation

/// Injectable time source so transfer engines can back off without coupling to
/// the wall clock. Tests inject an immediate (or blocking) implementation.
struct Sleeper: Sendable {
    /// Suspends for `seconds`; throws `CancellationError` if the task is cancelled.
    var sleep: @Sendable (_ seconds: TimeInterval) async throws -> Void
}
