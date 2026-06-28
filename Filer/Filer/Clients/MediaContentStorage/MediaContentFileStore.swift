import Foundation

actor MediaContentFileStore {
    private let importsDirectory: URL
    private let downloadsDirectory: URL
    private let fileManager: FileManager

    init(
        root: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "FilerMediaContent"
        ),
        fileManager: FileManager = .default
    ) {
        importsDirectory = root.appending(path: "imports")
        downloadsDirectory = root.appending(path: "downloads")
        self.fileManager = fileManager
    }

    func storeImport(
        _ key: String,
        _ data: Data
    ) throws -> MediaContentStorageClient.StoredContent {
        try fileManager.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
        let destination = importURL(for: key)
        try data.write(to: destination, options: .atomic)
        return try storedContent(
            key: key,
            localURL: destination,
            fallbackSize: Int64(data.count)
        )
    }

    func listImports() throws -> [MediaContentStorageClient.StoredContent] {
        guard fileManager.fileExists(atPath: importsDirectory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: importsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.map { url in
            try storedContent(key: url.lastPathComponent, localURL: url, fallbackSize: 0)
        }
    }

    func removeImport(_ key: String) throws {
        try fileManager.removeItem(at: importURL(for: key))
    }

    func importUploadSource(
        _ key: String
    ) throws -> MediaContentStorageClient.UploadSource {
        let source = importURL(for: key)
        guard fileManager.fileExists(atPath: source.path) else {
            throw MediaContentStorageClient.MissingContent(key: key)
        }
        let size = (try? fileManager.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
        return MediaContentStorageClient.UploadSource(key: key, localURL: source, size: size)
    }

    func prepareDownloadTarget(
        _ key: String
    ) throws -> MediaContentStorageClient.DownloadTarget {
        try fileManager.createDirectory(
            at: downloadsDirectory,
            withIntermediateDirectories: true
        )
        let destination = downloadURL(for: key)
        fileManager.createFile(atPath: destination.path, contents: nil)
        return MediaContentStorageClient.DownloadTarget(key: key, localURL: destination)
    }

    func writeDownload(_ key: String, _ data: Data, _ offset: UInt64) throws {
        let destination = downloadURL(for: key)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: data)
    }

    private func importURL(for key: String) -> URL {
        importsDirectory.appending(path: key)
    }

    private func downloadURL(for key: String) -> URL {
        downloadsDirectory.appending(path: key)
    }

    private func storedContent(
        key: String,
        localURL: URL,
        fallbackSize: Int64
    ) throws -> MediaContentStorageClient.StoredContent {
        let values = try localURL.resourceValues(forKeys: [.contentModificationDateKey])
        let size =
            (try? fileManager.attributesOfItem(atPath: localURL.path)[.size] as? Int64)
                ?? fallbackSize
        return MediaContentStorageClient.StoredContent(
            key: key,
            size: size,
            modifiedAt: values.contentModificationDate,
            localURL: localURL
        )
    }
}
