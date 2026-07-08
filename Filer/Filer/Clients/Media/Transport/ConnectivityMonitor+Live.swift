import Foundation
import Network

extension ConnectivityMonitor {
    /// Backed by `NWPathMonitor` — the only place Network.framework is imported.
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
