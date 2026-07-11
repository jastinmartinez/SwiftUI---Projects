@testable import Filer
import Foundation
import Testing

struct FileItemTests {
    @Test func withStatusReplacesOnlyStatus() {
        let metadata = MediaMetadata.sample(id: "a.jpg", name: "A", size: 100)
        let item = FileItem(remote: metadata)
        let next = item.with(status: .local(URL(fileURLWithPath: "/tmp/a.jpg")))

        #expect(next.metadata == metadata)
        #expect(next.id == "a.jpg")
        #expect(next.name == "A")
        #expect(next.contentType == "image/jpeg")
        #expect(next.kind == .image)
        #expect(next.size == 100)
        #expect(next.status == .local(URL(fileURLWithPath: "/tmp/a.jpg")))
    }

    @Test func importingInitStartsUploading() {
        let media = ImportedMedia.sample(id: "u.mp4", name: "Clip", contentType: "video/mp4", kind: .video, size: 12_000_000)
        let item = FileItem(importing: media)

        #expect(item.id == "u.mp4")
        #expect(item.name == "Clip")
        #expect(item.kind == .video)
        #expect(item.size == 12_000_000)
        #expect(item.status == .uploading(.pending(total: 12_000_000), isReconnecting: false))
    }

    @Test func uploadedInitLandsLocal() {
        let url = URL(fileURLWithPath: "/tmp/u.mp4")
        let media = ImportedMedia.sample(id: "u.mp4", name: "Clip", contentType: "video/mp4", kind: .video, size: 12_000_000, fileURL: url)
        let item = FileItem(uploaded: media)

        #expect(item.status == .local(url))
        #expect(item.id == "u.mp4")
    }

    @Test func remoteInitStartsRemote() {
        let metadata = MediaMetadata.sample(id: "remote.jpg", name: "Remote", size: nil)
        let item = FileItem(remote: metadata)

        #expect(item.metadata == metadata)
        #expect(item.status == .remote)
    }
}
