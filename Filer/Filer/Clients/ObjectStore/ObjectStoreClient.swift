import Foundation

struct ObjectStoreClient: Sendable {
    struct Write: Equatable, Sendable {
        let id: String
        let data: Data
    }

    struct StoredObject: Equatable, Sendable {
        let id: String
        let size: Int64
        let modifiedAt: Date?
        let fileURL: URL?
    }

    var put: @Sendable (_ object: Write) async throws -> StoredObject
    var list: @Sendable () async throws -> [StoredObject]
    var remove: @Sendable (_ id: String) async throws -> Void
}
