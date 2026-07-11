@testable import Filer
import Foundation
import Testing

struct SupabaseUploadTests {
    @Test func endpointIsResumableUploadPath() throws {
        let upload = try SupabaseUpload.request(for: makeMedia(), config: makeConfig())
        #expect(upload.endpoint.absoluteString == "https://xyz.supabase.co/storage/v1/upload/resumable")
    }

    @Test func commonHeadersAreAuthAndCreateHeadersAreMetadata() throws {
        let media = makeMedia()
        let config = try makeConfig()
        let upload = SupabaseUpload.request(for: media, config: config)

        #expect(upload.commonHeaders == SupabaseStorageHeaders.auth(config: config))
        #expect(upload.createHeaders == SupabaseStorageHeaders.create(media: media, config: config))
    }

    // MARK: - Helpers

    private func makeConfig() throws -> SupabaseConfig { try .sample() }
    private func makeMedia() -> ImportedMedia { .sample() }
}
