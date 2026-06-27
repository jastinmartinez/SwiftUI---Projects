import Foundation

extension ObjectStoreClient {
    nonisolated static func live(
        root: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "FilerImportCache"),
        fileManager: FileManager = .default
    ) -> ObjectStoreClient {
        ObjectStoreClient(
            put: { object in
                try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
                let destination = root.appending(path: object.id)
                try object.data.write(to: destination, options: .atomic)
                let size = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int64)
                    ?? Int64(object.data.count)
                let modifiedAt = (try? destination.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return StoredObject(id: object.id, size: size, modifiedAt: modifiedAt, fileURL: destination)
            },
            list: {
                guard fileManager.fileExists(atPath: root.path) else { return [] }
                let urls = try fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
                return try urls.map { url in
                    let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
                    let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    return StoredObject(
                        id: url.lastPathComponent,
                        size: size,
                        modifiedAt: values.contentModificationDate,
                        fileURL: url
                    )
                }
            },
            remove: { id in
                try fileManager.removeItem(at: root.appending(path: id))
            }
        )
    }
}
