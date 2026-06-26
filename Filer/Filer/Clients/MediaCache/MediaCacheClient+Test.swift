import Dependencies

extension MediaCacheClient: TestDependencyKey {
    static let testValue = MediaCacheClient()
}
