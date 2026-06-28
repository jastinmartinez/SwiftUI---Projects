@testable import Filer
import Foundation
import Testing

struct SupabaseUploadTests {
    @Test func endpointIsResumableUploadPath() throws {
        let upload = try SupabaseUpload.request(for: makeMedia(), config: makeConfig())
        #expect(upload.endpoint.absoluteString == "https://xyz.supabase.co/storage/v1/upload/resumable")
    }

    @Test func headersUseSupabaseStorageUploadHeaders() throws {
        let media = makeMedia()
        let config = try makeConfig()
        let upload = SupabaseUpload.request(for: media, config: config)

        #expect(upload.headers == SupabaseStorageHeaders.upload(media: media, config: config))
    }

    // MARK: - Helpers

    private func makeConfig() throws -> SupabaseConfig {
        let projectURL = try #require(URL(string: "https://xyz.supabase.co"))
        return SupabaseConfig(projectURL: projectURL, anonKey: "anon-123", bucket: "media")
    }

    private func makeMedia() -> ImportedMedia {
        ImportedMedia(
            metadata: MediaMetadata(
                id: "abc.jpg",
                name: "Holiday Photo",
                contentType: "image/jpeg",
                kind: .image,
                size: 2048
            ),
            fileURL: URL(fileURLWithPath: "/tmp/abc.jpg")
        )
    }
}
