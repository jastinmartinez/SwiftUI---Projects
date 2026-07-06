import Foundation
import Network

/// Injectable connectivity signal. Transfer engines await `stream()` to learn
/// when the network path is usable again, without importing Network.framework
/// themselves. The live implementation is backed by `NWPathMonitor`.
struct ConnectivityMonitor: Sendable {
    /// Emits the current online state and every subsequent change.
    /// `true` == the network path is satisfied.
    var stream: @Sendable () -> AsyncStream<Bool>
}

extension ConnectivityMonitor {
    static let live = ConnectivityMonitor(
        stream: {
            AsyncStream { continuation in
                let monitor = NWPathMonitor()
                monitor.pathUpdateHandler = { path in
                    continuation.yield(path.status == .satisfied)
                }
                let queue = DispatchQueue(label: "com.filer.connectivity")
                monitor.start(queue: queue)
                continuation.onTermination = { _ in monitor.cancel() }
            }
        }
    )
}
