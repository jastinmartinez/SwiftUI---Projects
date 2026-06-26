@testable import Filer
import Foundation
import Testing

struct SupabaseUploadTests {
    private func makeConfig() -> SupabaseConfig {
        SupabaseConfig(
            projectURL: URL(string: "https://xyz.supabase.co")!,
            anonKey: "anon-123",
            bucket: "media"
        )
    }

    private func makeMedia() -> ImportedMedia {
        ImportedMedia(
            id: "abc.jpg", name: "Holiday Photo",
            fileURL: URL(fileURLWithPath: "/tmp/abc.jpg"),
            contentType: "image/jpeg", kind: .image, size: 2048
        )
    }

    @Test func endpointIsResumableUploadPath() {
        let upload = SupabaseUpload(makeMedia(), config: makeConfig())
        #expect(upload.endpoint.absoluteString == "https://xyz.supabase.co/storage/v1/upload/resumable")
    }

    @Test func headersCarryAuthApikeyAndUpsert() {
        let upload = SupabaseUpload(makeMedia(), config: makeConfig())
        #expect(upload.headers["Authorization"] == "Bearer anon-123")
        #expect(upload.headers["apikey"] == "anon-123")
        #expect(upload.headers["x-upsert"] == "true")
    }

    @Test func uploadMetadataIsCommaJoinedBase64KeyValues() {
        let upload = SupabaseUpload(makeMedia(), config: makeConfig())
        let raw = try! #require(upload.headers["Upload-Metadata"])

        // parse "<key> <base64>,<key> <base64>,…" back into a dict of decoded values
        var decoded: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: " ", maxSplits: 1)
            let key = String(parts[0])
            let value = String(data: Data(base64Encoded: String(parts[1]))!, encoding: .utf8)!
            decoded[key] = value
        }

        #expect(decoded["bucketName"] == "media")
        #expect(decoded["objectName"] == "abc.jpg")
        #expect(decoded["contentType"] == "image/jpeg")
        #expect(decoded["cacheControl"] == "3600")
    }

    @Test func uploadMetadataRoundTripsDisplayNameViaCustomKey() {
        // display-name round-trip: a custom "name" key holds the human filename
        let upload = SupabaseUpload(makeMedia(), config: makeConfig())
        let raw = try! #require(upload.headers["Upload-Metadata"])

        var decoded: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: " ", maxSplits: 1)
            decoded[String(parts[0])] = String(data: Data(base64Encoded: String(parts[1]))!, encoding: .utf8)!
        }
        #expect(decoded["name"] == "Holiday Photo")
    }
}
