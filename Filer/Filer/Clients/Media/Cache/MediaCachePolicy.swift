import Foundation

struct MediaCachePolicy: Sendable {
    let timeToLive: TimeInterval

    /// Keys whose backing file is older than `timeToLive` relative to `now`.
    func expiredKeys(in imports: [MediaCacheClient.StoredContent], now: Date) -> [String] {
        imports.compactMap { stored in
            guard let modifiedAt = stored.modifiedAt else { return nil }
            return now.timeIntervalSince(modifiedAt) > timeToLive ? stored.key : nil
        }
    }
}

extension MediaCachePolicy {
    static let `default` = MediaCachePolicy(timeToLive: 60 * 60 * 24)
}
