@testable import Filer
import Foundation
import Testing

@Suite("MediaRemoteClient")
struct MediaRemoteClientTests {
    // uploadRequest is a pure mapping over SupabaseUpload.request; assert it carries
    // the same endpoint and header split. list/downloadRequest hit the Supabase SDK
    // and are intentionally not unit-tested here.
    @Test func uploadRequestMirrorsSupabaseUploadRequest() throws {
        let config = try makeConfig()
        let media = makeMedia()
        let client = MediaRemoteClient.live(config: config)

        let request = client.uploadRequest(media)
        let expected = SupabaseUpload.request(for: media, config: config)

        #expect(request.endpoint == expected.endpoint)
        #expect(request.commonHeaders == expected.commonHeaders)
        #expect(request.createHeaders == expected.createHeaders)
    }

    @Test func uploadRequestEndpointIsResumableUploadPath() throws {
        let client = try MediaRemoteClient.live(config: makeConfig())
        let request = client.uploadRequest(makeMedia())
        #expect(request.endpoint.absoluteString == "https://xyz.supabase.co/storage/v1/upload/resumable")
    }

    // downloadRequest's URL comes from the SDK's offline getPublicURL, and its headers
    // are the pure SupabaseStorageHeaders.download(config:) — both assertable without network.
    @Test func downloadRequestCarriesDownloadHeadersAndPublicURL() throws {
        let config = try makeConfig()
        let client = MediaRemoteClient.live(config: config)

        let request = try client.downloadRequest(makeFile())

        #expect(request.headers == SupabaseStorageHeaders.download(config: config))
        #expect(request.url.absoluteString.contains("media/abc.jpg"))
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

    private func makeFile() -> FileItem {
        FileItem(
            remote: MediaMetadata(
                id: "abc.jpg",
                name: "Holiday Photo",
                contentType: "image/jpeg",
                kind: .image,
                size: 2048
            )
        )
    }
}
