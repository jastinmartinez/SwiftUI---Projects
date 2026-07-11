@testable import Filer
import Testing

struct MediaKindTests {
    @Test func imageMimeTypesMapToImage() {
        #expect(MediaKind(mimeType: "image/jpeg") == .image)
        #expect(MediaKind(mimeType: "image/png") == .image)
    }

    @Test func videoMimeTypesMapToVideo() {
        #expect(MediaKind(mimeType: "video/mp4") == .video)
        #expect(MediaKind(mimeType: "video/quicktime") == .video)
    }

    @Test func nonMediaMimeTypesAreRejected() {
        #expect(MediaKind(mimeType: "application/pdf") == nil)
        #expect(MediaKind(mimeType: "text/plain") == nil)
    }

    @Test func missingMimeTypesAreRejected() {
        #expect(MediaKind(mimeType: nil) == nil)
        #expect(MediaKind(mimeType: "") == nil)
    }
}
