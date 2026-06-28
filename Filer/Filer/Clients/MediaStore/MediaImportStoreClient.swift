import Dependencies
import Foundation

struct MediaImportStoreClient: Sendable {
    typealias Store = @Sendable (_ payload: MediaImportClient.Payload) async throws -> ImportedMedia
    typealias RemoveExpired = @Sendable () async throws -> Void

    var store: Store = { _ in throw Unimplemented() }
    var removeExpired: RemoveExpired = { throw Unimplemented() }
}

extension MediaImportStoreClient {
    static let defaultTimeToLive: TimeInterval = 60 * 60 * 24

    struct Unimplemented: Error {}

    static func expiredKeys(
        in imports: [MediaContentStorageClient.StoredContent],
        now: Date,
        timeToLive: TimeInterval
    ) -> [String] {
        imports.compactMap { stored in
            guard let modifiedAt = stored.modifiedAt else { return nil }
            return now.timeIntervalSince(modifiedAt) > timeToLive ? stored.key : nil
        }
    }
}

extension DependencyValues {
    var mediaImportStore: MediaImportStoreClient {
        get { self[MediaImportStoreClient.self] }
        set { self[MediaImportStoreClient.self] = newValue }
    }
}
