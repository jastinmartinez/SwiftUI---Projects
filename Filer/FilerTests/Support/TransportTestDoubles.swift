@testable import Filer
import Foundation

extension Sleeper {
    /// Returns immediately — no real waiting in tests.
    static let immediate = Sleeper { _ in }

    /// Blocks until cancelled — for exercising cancellation paths.
    static let blocking = Sleeper { _ in try await Task.sleep(for: .seconds(3600)) }
}

extension ConnectivityMonitor {
    /// Reports online immediately.
    static let alwaysOnline = ConnectivityMonitor(stream: {
        AsyncStream { continuation in
            continuation.yield(true)
            continuation.finish()
        }
    })

    /// Reports offline and never recovers.
    static let offlineForever = ConnectivityMonitor(stream: {
        AsyncStream { continuation in
            continuation.yield(false)
            // Never finishes and never yields true.
        }
    })
}
