@testable import Filer
import Foundation
import Testing

struct TUSUploadHeadersTests {
    @Test func createRequestIncludesProtocolLengthAndProviderHeaders() throws {
        let request = try TUSUploadHeaders.createRequest(
            endpoint: endpoint(),
            uploadLength: 12,
            headers: ["Upload-Metadata": "name dGVzdA=="]
        )

        #expect(try request.url == endpoint())
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
        #expect(request.value(forHTTPHeaderField: "Upload-Length") == "12")
        #expect(request.value(forHTTPHeaderField: "Upload-Metadata") == "name dGVzdA==")
    }

    @Test func patchRequestIncludesOffsetAndContentType() throws {
        let request = try TUSUploadHeaders.patchRequest(uploadURL: uploadURL(), offset: 6, headers: [:])

        #expect(try request.url == uploadURL())
        #expect(request.httpMethod == "PATCH")
        #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
        #expect(request.value(forHTTPHeaderField: "Upload-Offset") == "6")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/offset+octet-stream")
    }

    @Test func patchRequestCarriesProviderHeadersAndProtocolWinsCollisions() throws {
        let request = try TUSUploadHeaders.patchRequest(
            uploadURL: uploadURL(),
            offset: 6,
            headers: ["apikey": "anon-key", "Content-Type": "text/plain"]
        )

        // Provider headers pass through untouched...
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
        // ...but a provider value that collides with a protocol header loses to the protocol.
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/offset+octet-stream")
    }

    @Test func headRequestIncludesProtocolVersion() throws {
        let request = try TUSUploadHeaders.headRequest(uploadURL: uploadURL(), headers: [:])

        #expect(try request.url == uploadURL())
        #expect(request.httpMethod == "HEAD")
        #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
    }

    @Test func headRequestCarriesProviderHeaders() throws {
        let request = try TUSUploadHeaders.headRequest(
            uploadURL: uploadURL(),
            headers: ["apikey": "anon-key", "Authorization": "Bearer anon-key"]
        )

        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon-key")
        #expect(request.value(forHTTPHeaderField: "Tus-Resumable") == "1.0.0")
    }

    // MARK: - Helpers

    private func endpoint() throws -> URL {
        try #require(URL(string: "https://example.supabase.co/storage/v1/upload/resumable"))
    }

    private func uploadURL() throws -> URL {
        try #require(URL(string: "https://example.supabase.co/storage/v1/upload/resumable/upload-1"))
    }
}
