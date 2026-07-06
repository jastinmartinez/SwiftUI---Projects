import Foundation

actor MediaCacheStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Whole-file atomic write (imports). Creates the enclosing directory.
    func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Ranged write at a byte offset (download chunks).
    func write(_ data: Data, to url: URL, at offset: UInt64) throws {
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.seek(toOffset: offset)
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    func read(at url: URL, offset: Int, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = handle.readData(ofLength: length)
            try handle.close()
            return data
        } catch {
            try? handle.close()
            throw error
        }
    }

    func size(at url: URL) -> Int64? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64
    }

    func modificationDate(at url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func exists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func remove(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    /// Ensures an empty file exists at `url` (download target), creating the directory first.
    func makeFileIfNeeded(at url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
    }

    func contents(of directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
    }
}
