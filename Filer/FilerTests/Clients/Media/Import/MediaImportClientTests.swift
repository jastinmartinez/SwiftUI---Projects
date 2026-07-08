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

    @Test func fileExtension_mapsPngType() {
        #expect(MediaImportClient.fileExtension(forContentType: "image/png") == "png")
    }

    @Test func fileExtension_unknownTypeReturnsNil() {
        #expect(MediaImportClient.fileExtension(forContentType: "application/x-nonsense") == nil)
    }

    @Test func objectID_combinesUUIDAndExtension() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000AB"))
        let object = MediaImportClient.objectID(id, contentType: "image/jpeg")
        #expect(object == "00000000-0000-0000-0000-0000000000AB.jpeg")
    }

    @Test func objectID_unknownTypeReturnsNil() throws {
        let id = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(MediaImportClient.objectID(id, contentType: "application/x-nonsense") == nil)
    }
}
