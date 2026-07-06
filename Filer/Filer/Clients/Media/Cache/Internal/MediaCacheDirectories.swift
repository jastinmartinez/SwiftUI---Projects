import Foundation

struct MediaCacheDirectories: Sendable {
    let imports: URL
    let downloads: URL

    func importURL(for key: String) -> URL { imports.appending(path: key) }
    func downloadURL(for key: String) -> URL { downloads.appending(path: key) }
}

extension MediaCacheDirectories {
    static var defaultRoot: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "FilerMediaContent")
    }

    static func temporary(root: URL = defaultRoot) -> MediaCacheDirectories {
        MediaCacheDirectories(
            imports: root.appending(path: "imports"),
            downloads: root.appending(path: "downloads")
        )
    }
}
