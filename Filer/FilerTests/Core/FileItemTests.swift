@testable import Filer
import Foundation
import Testing

struct FileItemTests {
    @Test func withStatusReplacesOnlyStatus() {
        let item = FileItem(id: "a.jpg", name: "A", kind: .image, size: 100, status: .remote)
        let next = item.with(status: .local(URL(fileURLWithPath: "/tmp/a.jpg")))

        #expect(next.id == "a.jpg")
        #expect(next.name == "A")
        #expect(next.kind == .image)
        #expect(next.size == 100)
        #expect(next.status == .local(URL(fileURLWithPath: "/tmp/a.jpg")))
    }

    @Test func statusEquality() {
        let remote = FileItem.Status.remote
        #expect(remote == .remote)

        let url = URL(fileURLWithPath: "/tmp/f.jpg")
        #expect(FileItem.Status.local(url) == .local(url))
        #expect(FileItem.Status.local(url) != .remote)
    }

    @Test func importingInitStartsUploading() {
        let media = ImportedMedia(
            id: "u.mp4", name: "Clip", fileURL: URL(fileURLWithPath: "/tmp/u.mp4"),
            contentType: "video/mp4", kind: .video, size: 12_000_000
        )
        let item = FileItem(importing: media)

        #expect(item.id == "u.mp4")
        #expect(item.name == "Clip")
        #expect(item.kind == .video)
        #expect(item.size == 12_000_000)
        #expect(item.status == .uploading(.start(total: 12_000_000)))
    }

    @Test func uploadedInitLandsLocal() {
        let url = URL(fileURLWithPath: "/tmp/u.mp4")
        let media = ImportedMedia(
            id: "u.mp4", name: "Clip", fileURL: url,
            contentType: "video/mp4", kind: .video, size: 12_000_000
        )
        let item = FileItem(uploaded: media)

        #expect(item.status == .local(url))
        #expect(item.id == "u.mp4")
    }

    // MARK: Kind(mimeType:)

    @Test func imageMimeMapsToImageKind() {
        #expect(FileItem.Kind(mimeType: "image/jpeg") == .image)
        #expect(FileItem.Kind(mimeType: "image/png") == .image)
    }

    @Test func videoMimeMapsToVideoKind() {
        #expect(FileItem.Kind(mimeType: "video/mp4") == .video)
        #expect(FileItem.Kind(mimeType: "video/quicktime") == .video)
    }

    @Test func nonMediaMimeIsNil() {
        #expect(FileItem.Kind(mimeType: "application/pdf") == nil)
        #expect(FileItem.Kind(mimeType: "text/plain") == nil)
    }

    @Test func nilOrEmptyMimeIsNil() {
        #expect(FileItem.Kind(mimeType: nil) == nil)
        #expect(FileItem.Kind(mimeType: "") == nil)
    }
}
