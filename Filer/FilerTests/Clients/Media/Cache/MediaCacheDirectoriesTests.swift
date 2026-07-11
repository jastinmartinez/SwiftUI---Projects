@testable import Filer
import Foundation
import Testing

@Suite struct MediaCacheDirectoriesTests {
    private let directories = MediaCacheDirectories.temporary(root: URL(fileURLWithPath: "/cache"))

    @Test func importURLNestsKeyUnderImports() {
        #expect(directories.importURL(for: "photo.jpeg").path == "/cache/imports/photo.jpeg")
    }

    @Test func downloadURLNestsKeyUnderDownloads() {
        #expect(directories.downloadURL(for: "clip.mov").path == "/cache/downloads/clip.mov")
    }
}
