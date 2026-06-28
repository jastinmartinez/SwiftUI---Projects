@testable import Filer
import Foundation
import Testing

struct FilePreviewModelTests {
    @Test func imageKindMapsToImageWithURL() {
        let url = URL(filePath: "/tmp/a.jpg")
        #expect(FilePreviewView.Model(FilesFeature.PreviewItem(url: url, kind: .image)) == .image(url))
    }

    @Test func videoKindMapsToVideoWithURL() {
        let url = URL(filePath: "/tmp/a.mov")
        #expect(FilePreviewView.Model(FilesFeature.PreviewItem(url: url, kind: .video)) == .video(url))
    }

    @Test func previewItemIdIsItsURL() {
        let url = URL(fileURLWithPath: "/tmp/abc.jpg")
        let item = FilesFeature.PreviewItem(url: url, kind: .image)
        #expect(item.id == url)
        #expect(item.kind == .image)
    }
}
