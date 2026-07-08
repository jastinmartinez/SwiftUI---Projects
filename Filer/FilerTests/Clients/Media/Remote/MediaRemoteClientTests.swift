@testable import Filer
import Foundation
import Testing

@Suite("MediaRemoteClient")
struct MediaRemoteClientTests {
    // uploadRequest is a pure mapping over SupabaseUpload.request; assert it carries
    // the same endpoint and header split. list/downloadRequest hit the Supabase SDK
    // and are intentionally not unit-tested here.
    @Test func uploadRequestMirrorsSupabaseUploadRequest() {
        let config = makeConfig()
        let media = makeMedia()
        let client = MediaRemoteClient.live(config: config)

        let request = client.uploadRequest(media)
        let expected = SupabaseUpload.request(for: media, config: config)

        #expect(request.endpoint == expected.endpoint)
        #expect(request.commonHeaders == expected.commonHeaders)
        #expect(request.createHeaders == expected.createHeaders)
    }

    @Test func uploadRequestEndpointIsResumableUploadPath() {
        let client = MediaRemoteClient.live(config: makeConfig())
        let request = client.uploadRequest(makeMedia())
        #expect(request.endpoint.absoluteString == "https://xyz.supabase.co/storage/v1/upload/resumable")
    }

    // downloadRequest's URL comes from the SDK's offline getPublicURL, and its headers
    // are the pure SupabaseStorageHeaders.download(config:) — both assertable without network.
    @Test func downloadRequestCarriesDownloadHeadersAndPublicURL() throws {
        let config = makeConfig()
        let client = MediaRemoteClient.live(config: config)

        let request = try client.downloadRequest(makeFile())

        #expect(request.headers == SupabaseStorageHeaders.download(config: config))
        #expect(request.url.absoluteString.contains("media/abc.jpg"))
    }

    // MARK: - Helpers

    private func makeConfig() -> SupabaseConfig { .sample() }
    private func makeMedia() -> ImportedMedia { .sample() }
    private func makeFile() -> FileItem { .sample() }
}
