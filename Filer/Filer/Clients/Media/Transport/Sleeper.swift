import Foundation

/// Injectable time source so transfer engines can back off without coupling to
/// the wall clock. Tests inject an immediate (or blocking) implementation.
struct Sleeper: Sendable {
    /// Suspends for `seconds`; throws `CancellationError` if the task is cancelled.
    var sleep: @Sendable (_ seconds: TimeInterval) async throws -> Void
}

extension Sleeper {
    static let live = Sleeper { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }
}
