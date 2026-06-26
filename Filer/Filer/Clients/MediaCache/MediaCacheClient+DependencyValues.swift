import Dependencies

extension DependencyValues {
    var mediaCache: MediaCacheClient {
        get { self[MediaCacheClient.self] }
        set { self[MediaCacheClient.self] = newValue }
    }
}
