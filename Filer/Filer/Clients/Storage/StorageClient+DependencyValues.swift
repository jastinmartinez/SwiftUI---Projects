import Dependencies

extension DependencyValues {
    var storage: StorageClient {
        get { self[StorageClient.self] }
        set { self[StorageClient.self] = newValue }
    }
}
