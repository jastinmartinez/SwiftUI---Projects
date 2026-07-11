/// Injectable connectivity signal. Transfer engines await `stream()` to learn
/// when the network path is usable again, without importing Network.framework
/// themselves. The live implementation is backed by `NWPathMonitor`.
struct ConnectivityMonitor: Sendable {
    /// Emits the current online state and every subsequent change.
    /// `true` == the network path is satisfied.
    var stream: @Sendable () -> AsyncStream<Bool>
}
