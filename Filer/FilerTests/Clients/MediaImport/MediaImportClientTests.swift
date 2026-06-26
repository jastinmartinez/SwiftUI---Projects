@testable import Filer
import Foundation
import Testing

@Suite struct MediaImportClientTests {
    @Test func fileExtension_mapsKnownImageType() {
        #expect(MediaImportClient.fileExtension(forContentType: "image/jpeg") == "jpeg")
    }

    @Test func fileExtension_mapsKnownVideoType() {
        #expect(MediaImportClient.fileExtension(forContentType: "video/quicktime") == "mov")
    }

    @Test func fileExtension_pngRoundTrips() {
        #expect(MediaImportClient.fileExtension(forContentType: "image/png") == "png")
    }

    @Test func fileExtension_unknownTypeReturnsNil() {
        #expect(MediaImportClient.fileExtension(forContentType: "application/x-nonsense") == nil)
    }

    @Test func objectID_combinesUUIDAndExtension() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!
        let object = MediaImportClient.objectID(id, contentType: "image/jpeg")
        #expect(object == "00000000-0000-0000-0000-0000000000AB.jpeg")
    }

    @Test func objectID_unknownTypeReturnsNil() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        #expect(MediaImportClient.objectID(id, contentType: "application/x-nonsense") == nil)
    }

    @Test func payloadCarriesImportMetadata() {
        let payload = MediaImportPayload(
            id: "abc.jpeg",
            name: "Photo",
            data: Data([1, 2, 3]),
            contentType: "image/jpeg",
            kind: .image
        )

        #expect(payload.id == "abc.jpeg")
        #expect(payload.name == "Photo")
        #expect(payload.data == Data([1, 2, 3]))
        #expect(payload.contentType == "image/jpeg")
        #expect(payload.kind == .image)
    }
}
