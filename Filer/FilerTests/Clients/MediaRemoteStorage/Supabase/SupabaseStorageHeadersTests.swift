@testable import Filer
import Foundation
import Testing

struct SupabaseStorageHeadersTests {
    @Test func authHeadersIncludeBearerAndApiKey() throws {
        let config = try #require(makeConfig())
        let headers = SupabaseStorageHeaders.auth(config: config)

        #expect(headers["Authorization"] == "Bearer anon")
        #expect(headers["apikey"] == "anon")
    }

    @Test func uploadHeadersIncludeAuthMetadataAndUpsert() throws {
        let config = try #require(makeConfig())
        let headers = SupabaseStorageHeaders.upload(media: media, config: config)
        let metadata = try decodeUploadMetadata(headers)

        #expect(headers["Authorization"] == "Bearer anon")
        #expect(headers["apikey"] == "anon")
        #expect(headers["x-upsert"] == "true")
        #expect(metadata["bucketName"] == "media")
        #expect(metadata["objectName"] == "abc.jpg")
        #expect(metadata["contentType"] == "image/jpeg")
        #expect(metadata["cacheControl"] == "3600")
        #expect(metadata["name"] == "Photo")
    }

    @Test func downloadHeadersIncludeAuthOnly() throws {
        let config = try #require(makeConfig())
        let headers = SupabaseStorageHeaders.download(config: config)

        #expect(headers == [
            "Authorization": "Bearer anon",
            "apikey": "anon",
        ])
    }

    private func makeConfig() -> SupabaseConfig? {
        guard let projectURL = URL(string: "https://example.supabase.co") else {
            return nil
        }

        return SupabaseConfig(
            projectURL: projectURL,
            anonKey: "anon",
            bucket: "media"
        )
    }

    private var media: ImportedMedia {
        ImportedMedia(
            metadata: MediaMetadata(
                id: "abc.jpg",
                name: "Photo",
                contentType: "image/jpeg",
                kind: .image,
                size: 12
            ),
            fileURL: URL(fileURLWithPath: "/tmp/abc.jpg")
        )
    }

    private func decodeUploadMetadata(_ headers: [String: String]) throws -> [String: String] {
        let rawMetadata = try #require(headers["Upload-Metadata"])
        var decoded: [String: String] = [:]

        for pair in rawMetadata.split(separator: ",") {
            let parts = pair.split(separator: " ", maxSplits: 1)
            let key = try #require(parts.first)
            let encodedValue = try #require(parts.dropFirst().first)
            let data = try #require(Data(base64Encoded: String(encodedValue)))
            let value = try #require(String(data: data, encoding: .utf8))

            decoded[String(key)] = value
        }

        return decoded
    }
}
