import Foundation

struct ObjectStoreClient: Sendable {
    struct Write: Equatable, Sendable {
        let id: String
        let data: Data

        nonisolated init(id: String, data: Data) {
            self.id = id
            self.data = data
        }
    }

    struct StoredObject: Equatable, Sendable {
        let id: String
        let size: Int64
        let modifiedAt: Date?
        let fileURL: URL?

        nonisolated init(id: String, size: Int64, modifiedAt: Date?, fileURL: URL?) {
            self.id = id
            self.size = size
            self.modifiedAt = modifiedAt
            self.fileURL = fileURL
        }
    }

    var put: @Sendable (_ object: Write) async throws -> StoredObject
    var list: @Sendable () async throws -> [StoredObject]
    var remove: @Sendable (_ id: String) async throws -> Void

    nonisolated init(
        put: @escaping @Sendable (_ object: Write) async throws -> StoredObject,
        list: @escaping @Sendable () async throws -> [StoredObject],
        remove: @escaping @Sendable (_ id: String) async throws -> Void
    ) {
        self.put = put
        self.list = list
        self.remove = remove
    }
}
