import Dependencies

/// Thrown by the fail-loud `testValue` streams to name the endpoint a test forgot to
/// override.
struct UnimplementedError: Error {
    let endpoint: String
    init(_ endpoint: String) { self.endpoint = endpoint }
}

extension StorageClient: TestDependencyKey {
    /// Fail-loud: no canned success. The non-throwing upload/download endpoints return a
    /// stream that IMMEDIATELY THROWS — a test that exercises a transfer without overriding
    /// the endpoint fails with a named error instead of silently "finishing". `list` is left
    /// at its `@DependencyClient` unimplemented default.
    static let testValue: StorageClient = {
        var client = StorageClient()
        client.upload = { _ in AsyncThrowingStream { $0.finish(throwing: UnimplementedError("storage.upload")) } }
        client.download = { _ in AsyncThrowingStream { $0.finish(throwing: UnimplementedError("storage.download")) } }
        return client
    }()
}
