import Foundation

extension MediaCacheClient {
    enum Failure: Error {
        case unsupportedStorageLocation
    }

    static let defaultTimeToLive: TimeInterval = 60 * 60 * 24

    static func expiredIDs(
        in objects: [ObjectStoreClient.StoredObject],
        now: Date,
        timeToLive: TimeInterval
    ) -> [String] {
        objects.compactMap { object in
            guard let modifiedAt = object.modifiedAt else { return nil }
            return now.timeIntervalSince(modifiedAt) > timeToLive ? object.id : nil
        }
    }
}
