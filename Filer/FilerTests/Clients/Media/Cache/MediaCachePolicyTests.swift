@testable import Filer
import Foundation
import Testing

@Suite struct MediaCachePolicyTests {
    private func stored(_ key: String, modifiedAt: Date?) -> MediaCacheClient.StoredContent {
        MediaCacheClient.StoredContent(
            key: key,
            size: 0,
            modifiedAt: modifiedAt,
            localURL: URL(fileURLWithPath: "/imports/\(key)")
        )
    }

    @Test func expiredKeysReturnsItemsOlderThanTimeToLive() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let policy = MediaCachePolicy(timeToLive: 100)
        let imports = [
            stored("fresh.jpeg", modifiedAt: now.addingTimeInterval(-50)),
            stored("stale.jpeg", modifiedAt: now.addingTimeInterval(-200)),
        ]

        #expect(policy.expiredKeys(in: imports, now: now) == ["stale.jpeg"])
    }

    @Test func expiredKeysIgnoresItemsWithoutModificationDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let policy = MediaCachePolicy(timeToLive: 0)

        #expect(policy.expiredKeys(in: [stored("unknown.jpeg", modifiedAt: nil)], now: now).isEmpty)
    }
}
